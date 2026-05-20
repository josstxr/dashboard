import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "@supabase/supabase-js"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
    const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY") ?? ""
    const authorization = req.headers.get("Authorization")

    if (!authorization || !serviceRoleKey) {
      return jsonResponse({ error: "Configuracion incompleta" }, 500)
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser()
    if (userError || !user) {
      return jsonResponse({ error: "No autenticado" }, 401)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    await deleteUserAppData(adminClient, user.id)

    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(user.id)
    if (deleteUserError) {
      return jsonResponse({ error: deleteUserError.message }, 500)
    }

    return jsonResponse({ ok: true }, 200)
  } catch (error) {
    const message = error instanceof Error ? error.message : "Error borrando cuenta"
    return jsonResponse({ error: message }, 500)
  }
})

async function deleteUserAppData(adminClient: ReturnType<typeof createClient>, userId: string) {
  await adminClient.from("daily_diets").delete().eq("user_id", userId)

  const { data: workouts } = await adminClient
    .from("workouts")
    .select("id")
    .eq("user_id", userId)
  const workoutIds = (workouts ?? []).map((row) => row.id).filter(Boolean)
  if (workoutIds.length > 0) {
    await adminClient.from("exercises").delete().in("workout_id", workoutIds)
  }

  const { data: diets } = await adminClient
    .from("diets")
    .select("id")
    .eq("user_id", userId)
  const dietIds = (diets ?? []).map((row) => row.id).filter(Boolean)
  if (dietIds.length > 0) {
    await adminClient.from("meals").delete().in("diet_id", dietIds)
  }

  await adminClient.from("workouts").delete().eq("user_id", userId)
  await adminClient.from("diets").delete().eq("user_id", userId)
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
