import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "@supabase/supabase-js"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

type LiveActivityEvent = "update" | "end"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const authorization = req.headers.get("Authorization")
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? ""

    if (!authorization || !supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse({ error: "Configuracion incompleta" }, 500)
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) {
      return jsonResponse({ error: "No autenticado" }, 401)
    }

    const body = await req.json()
    const event = (body.event?.toString() ?? "update") as LiveActivityEvent
    if (event !== "update" && event !== "end") {
      return jsonResponse({ error: "Evento invalido" }, 400)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: tokenRow, error: tokenError } = await adminClient
      .from("live_activity_tokens")
      .select("id, push_token")
      .eq("user_id", user.id)
      .eq("platform", "ios")
      .order("updated_at", { ascending: false })
      .limit(1)
      .maybeSingle()

    if (tokenError) {
      return jsonResponse({ error: tokenError.message }, 500)
    }
    if (!tokenRow?.push_token) {
      return jsonResponse({ ok: false, reason: "No hay Live Activity iOS registrada" }, 200)
    }

    const apnsPayload = buildApnsPayload(event, body.state)
    const apnsResult = await sendLiveActivityPush(tokenRow.push_token, apnsPayload)

    if (!apnsResult.ok) {
      return jsonResponse({ error: apnsResult.body }, apnsResult.status)
    }

    if (event === "end") {
      await adminClient.from("live_activity_tokens").delete().eq("id", tokenRow.id)
    }

    return jsonResponse({ ok: true }, 200)
  } catch (error) {
    const message = error instanceof Error ? error.message : "Error actualizando Live Activity"
    return jsonResponse({ error: message }, 500)
  }
})

function buildApnsPayload(event: LiveActivityEvent, state: unknown) {
  if (event === "end") {
    return {
      aps: {
        timestamp: Math.floor(Date.now() / 1000),
        event: "end",
        "dismissal-date": Math.floor(Date.now() / 1000),
      },
    }
  }

  const contentState = normalizeContentState(state)
  return {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: "update",
      "content-state": contentState,
    },
  }
}

function normalizeContentState(state: unknown) {
  const raw = isRecord(state) ? state : {}
  const now = Math.floor(Date.now() / 1000)
  const endTime = Number(raw.endTime ?? now)
  const isPaused = raw.isPaused === true

  const contentState: Record<string, unknown> = {
    title: raw.title?.toString() ?? "Entrenamiento",
    startTime: Number(raw.startTime ?? now),
    endTime,
    isPaused,
  }

  if (isPaused) {
    contentState.pausedRemaining = Number(raw.pausedRemaining ?? Math.max(0, endTime - now))
  }

  return contentState
}

async function sendLiveActivityPush(pushToken: string, payload: unknown) {
  const teamId = requiredEnv("APPLE_TEAM_ID")
  const keyId = requiredEnv("APPLE_KEY_ID")
  const bundleId = requiredEnv("APPLE_BUNDLE_ID")
  const privateKey = requiredEnv("APPLE_APNS_PRIVATE_KEY")
  const apnsEnv = Deno.env.get("APPLE_APNS_ENV") ?? "sandbox"
  const host = apnsEnv === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
  const jwt = await createApnsJwt(teamId, keyId, privateKey)

  const response = await fetch(`https://${host}/3/device/${pushToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": `${bundleId}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  })

  return {
    ok: response.ok,
    status: response.status,
    body: await response.text(),
  }
}

async function createApnsJwt(teamId: string, keyId: string, privateKeyPem: string) {
  const header = base64UrlJson({ alg: "ES256", kid: keyId })
  const claims = base64UrlJson({ iss: teamId, iat: Math.floor(Date.now() / 1000) })
  const signingInput = `${header}.${claims}`
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  const signature = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  ))
  return `${signingInput}.${base64Url(ecdsaSignatureToJose(signature))}`
}

function ecdsaSignatureToJose(signature: Uint8Array) {
  if (signature.length === 64) {
    return signature
  }

  let offset = 3
  let rLength = signature[offset++]
  if (signature[offset] === 0) {
    offset += 1
    rLength -= 1
  }
  const r = signature.slice(offset, offset + rLength)
  offset += rLength + 1
  let sLength = signature[offset++]
  if (signature[offset] === 0) {
    offset += 1
    sLength -= 1
  }
  const s = signature.slice(offset, offset + sLength)

  const jose = new Uint8Array(64)
  jose.set(r.slice(-32), 32 - Math.min(32, r.length))
  jose.set(s.slice(-32), 64 - Math.min(32, s.length))
  return jose
}

function pemToArrayBuffer(pem: string) {
  const normalized = pem.replace(/\\n/g, "\n")
  const base64 = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "")
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes.buffer
}

function base64UrlJson(value: unknown) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)))
}

function base64Url(bytes: Uint8Array) {
  let binary = ""
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name)
  if (!value) {
    throw new Error(`Falta secret ${name}`)
  }
  return value
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
