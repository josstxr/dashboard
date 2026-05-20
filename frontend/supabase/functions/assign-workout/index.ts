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
    if (user.user_metadata?.role !== "admin") {
      return jsonResponse({ error: "Solo admins pueden asignar rutinas" }, 403)
    }

    const body = await req.json()
    const targetEmail = body.target_email?.toString().trim().toLowerCase()
    const workout = body.workout
    if (!targetEmail || !workout?.name) {
      return jsonResponse({ error: "Falta correo destino o rutina" }, 400)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const targetUser = await findUserByEmail(adminClient, targetEmail)
    if (!targetUser) {
      return jsonResponse({ error: "No existe un usuario con ese correo" }, 404)
    }

    const { data: workoutRow, error: workoutError } = await adminClient
      .from("workouts")
      .insert({
        user_id: targetUser.id,
        name: workout.name?.toString() ?? "Rutina asignada",
        day_of_week: Number(workout.day_of_week ?? 1),
      })
      .select()
      .single()

    if (workoutError) {
      return jsonResponse({ error: workoutError.message }, 500)
    }

    const exercises = Array.isArray(workout.exercises) ? workout.exercises : []
    const rows = exercises.map((exercise) => ({
      workout_id: workoutRow.id,
      name: exercise.name?.toString() ?? "Ejercicio",
      sets: Number(exercise.sets ?? 0),
      reps: exercise.reps?.toString() ?? "-",
      rest_seconds: Number(exercise.rest_seconds ?? 0),
      notes: exercise.notes?.toString() ?? "",
    }))

    if (rows.length > 0) {
      const { error: exercisesError } = await adminClient
        .from("exercises")
        .insert(rows)
      if (exercisesError) {
        return jsonResponse({ error: exercisesError.message }, 500)
      }
    }

    return jsonResponse({ ok: true, workout_id: workoutRow.id }, 200)
  } catch (error) {
    const message = error instanceof Error ? error.message : "Error asignando rutina"
    return jsonResponse({ error: message }, 500)
  }
})

async function findUserByEmail(adminClient: ReturnType<typeof createClient>, email: string) {
  let page = 1
  const perPage = 1000
  while (page < 50) {
    const { data, error } = await adminClient.auth.admin.listUsers({
      page,
      perPage,
    })
    if (error) {
      throw error
    }
    const found = data.users.find((user) => user.email?.toLowerCase() === email)
    if (found || data.users.length < perPage) {
      return found ?? null
    }
    page += 1
  }
  return null
}

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  })
}
