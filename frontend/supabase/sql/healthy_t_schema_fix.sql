-- Healthy-T schema fix
-- Ejecuta esto en Supabase SQL Editor si ves errores como:
-- PGRST204: Could not find the 'day_of_week' column of 'workouts'

begin;

alter table public.workouts
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists name text not null default 'Rutina',
  add column if not exists day_of_week integer not null default 1;

alter table public.workouts
  drop constraint if exists workouts_day_of_week_check;

alter table public.workouts
  add constraint workouts_day_of_week_check
  check (day_of_week between 1 and 7);

alter table public.exercises
  add column if not exists workout_id uuid,
  add column if not exists name text not null default 'Ejercicio',
  add column if not exists sets integer not null default 0,
  add column if not exists reps text not null default '-',
  add column if not exists rest_seconds integer not null default 0,
  add column if not exists exercise_order integer not null default 0,
  add column if not exists notes text not null default '';

alter table public.diets
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists name text not null default 'Dieta',
  add column if not exists day_of_week integer not null default 1;

alter table public.diets
  drop constraint if exists diets_day_of_week_check;

alter table public.diets
  add constraint diets_day_of_week_check
  check (day_of_week between 1 and 7);

alter table public.meals
  add column if not exists diet_id uuid,
  add column if not exists name text not null default 'Comida',
  add column if not exists calories integer not null default 0,
  add column if not exists protein integer not null default 0,
  add column if not exists carbs integer not null default 0,
  add column if not exists fats integer not null default 0,
  add column if not exists notes text not null default '';

-- Estas políticas dependen de exercises.workout_id y meals.diet_id.
-- Hay que quitarlas antes de cambiar tipos o recrear FKs.
drop policy if exists exercises_select_own on public.exercises;
drop policy if exists exercises_insert_own on public.exercises;
drop policy if exists exercises_update_own on public.exercises;
drop policy if exists exercises_delete_own on public.exercises;

drop policy if exists meals_select_own on public.meals;
drop policy if exists meals_insert_own on public.meals;
drop policy if exists meals_update_own on public.meals;
drop policy if exists meals_delete_own on public.meals;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.exercises'::regclass
      and contype = 'f'
  loop
    execute format('alter table public.exercises drop constraint if exists %I', constraint_name);
  end loop;

  for constraint_name in
    select conname
    from pg_constraint
    where conrelid = 'public.meals'::regclass
      and contype = 'f'
  loop
    execute format('alter table public.meals drop constraint if exists %I', constraint_name);
  end loop;
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'workouts'
      and column_name = 'id'
      and udt_name = 'uuid'
  ) then
    alter table public.exercises
      alter column workout_id drop not null,
      alter column workout_id type uuid
      using case
        when workout_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then workout_id::text::uuid
        else null
      end;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'diets'
      and column_name = 'id'
      and udt_name = 'uuid'
  ) then
    alter table public.meals
      alter column diet_id drop not null,
      alter column diet_id type uuid
      using case
        when diet_id::text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
          then diet_id::text::uuid
        else null
      end;
  end if;
end $$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns child
    join information_schema.columns parent
      on parent.table_schema = 'public'
     and parent.table_name = 'workouts'
     and parent.column_name = 'id'
    where child.table_schema = 'public'
      and child.table_name = 'exercises'
      and child.column_name = 'workout_id'
      and child.udt_name = parent.udt_name
  ) then
    alter table public.exercises
      add constraint exercises_workout_id_fkey
      foreign key (workout_id) references public.workouts(id) on delete cascade;
  end if;

  if exists (
    select 1
    from information_schema.columns child
    join information_schema.columns parent
      on parent.table_schema = 'public'
     and parent.table_name = 'diets'
     and parent.column_name = 'id'
    where child.table_schema = 'public'
      and child.table_name = 'meals'
      and child.column_name = 'diet_id'
      and child.udt_name = parent.udt_name
  ) then
    alter table public.meals
      add constraint meals_diet_id_fkey
      foreign key (diet_id) references public.diets(id) on delete cascade;
  end if;
end $$;

alter table public.daily_diets
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists food_id bigint,
  add column if not exists name text not null default 'Comida registrada',
  add column if not exists meal_slot text,
  add column if not exists consumed_at date not null default current_date,
  add column if not exists calories integer not null default 0,
  add column if not exists protein integer not null default 0,
  add column if not exists carbs integer not null default 0,
  add column if not exists fats integer not null default 0,
  add column if not exists grams integer not null default 0,
  add column if not exists estimated_grams integer not null default 0,
  add column if not exists confidence numeric not null default 0,
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.pending_user_assignments (
  id uuid primary key default gen_random_uuid(),
  target_email text not null,
  assignment_type text not null check (assignment_type in ('workout', 'diet')),
  payload jsonb not null,
  assigned_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.live_activity_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  activity_id text not null,
  push_token text not null,
  platform text not null default 'ios',
  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, activity_id)
);

create index if not exists workouts_user_day_idx
  on public.workouts(user_id, day_of_week);

create index if not exists diets_user_day_idx
  on public.diets(user_id, day_of_week);

create index if not exists exercises_workout_idx
  on public.exercises(workout_id);

create index if not exists exercises_workout_order_idx
  on public.exercises(workout_id, exercise_order);

create index if not exists meals_diet_idx
  on public.meals(diet_id);

create index if not exists daily_diets_user_created_idx
  on public.daily_diets(user_id, created_at);

create index if not exists daily_diets_user_consumed_idx
  on public.daily_diets(user_id, consumed_at);

create index if not exists pending_assignments_email_idx
  on public.pending_user_assignments(lower(target_email), assignment_type);

create index if not exists live_activity_tokens_user_updated_idx
  on public.live_activity_tokens(user_id, updated_at desc);

alter table public.workouts enable row level security;
alter table public.exercises enable row level security;
alter table public.diets enable row level security;
alter table public.meals enable row level security;
alter table public.daily_diets enable row level security;
alter table public.pending_user_assignments enable row level security;
alter table public.live_activity_tokens enable row level security;

drop policy if exists workouts_select_own on public.workouts;
drop policy if exists workouts_insert_own on public.workouts;
drop policy if exists workouts_update_own on public.workouts;
drop policy if exists workouts_delete_own on public.workouts;

create policy workouts_select_own
  on public.workouts
  for select
  to authenticated
  using (user_id = auth.uid());

create policy workouts_insert_own
  on public.workouts
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy workouts_update_own
  on public.workouts
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy workouts_delete_own
  on public.workouts
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists live_activity_tokens_select_own on public.live_activity_tokens;
drop policy if exists live_activity_tokens_insert_own on public.live_activity_tokens;
drop policy if exists live_activity_tokens_update_own on public.live_activity_tokens;
drop policy if exists live_activity_tokens_delete_own on public.live_activity_tokens;

create policy live_activity_tokens_select_own
  on public.live_activity_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

create policy live_activity_tokens_insert_own
  on public.live_activity_tokens
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy live_activity_tokens_update_own
  on public.live_activity_tokens
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy live_activity_tokens_delete_own
  on public.live_activity_tokens
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists exercises_select_own on public.exercises;
drop policy if exists exercises_insert_own on public.exercises;
drop policy if exists exercises_update_own on public.exercises;
drop policy if exists exercises_delete_own on public.exercises;

create policy exercises_select_own
  on public.exercises
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.workouts
      where workouts.id = exercises.workout_id
        and workouts.user_id = auth.uid()
    )
  );

create policy exercises_insert_own
  on public.exercises
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.workouts
      where workouts.id = exercises.workout_id
        and workouts.user_id = auth.uid()
    )
  );

create policy exercises_update_own
  on public.exercises
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.workouts
      where workouts.id = exercises.workout_id
        and workouts.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.workouts
      where workouts.id = exercises.workout_id
        and workouts.user_id = auth.uid()
    )
  );

create policy exercises_delete_own
  on public.exercises
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.workouts
      where workouts.id = exercises.workout_id
        and workouts.user_id = auth.uid()
    )
  );

drop policy if exists diets_select_own on public.diets;
drop policy if exists diets_insert_own on public.diets;
drop policy if exists diets_update_own on public.diets;
drop policy if exists diets_delete_own on public.diets;

create policy diets_select_own
  on public.diets
  for select
  to authenticated
  using (user_id = auth.uid());

create policy diets_insert_own
  on public.diets
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy diets_update_own
  on public.diets
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy diets_delete_own
  on public.diets
  for delete
  to authenticated
  using (user_id = auth.uid());

drop policy if exists meals_select_own on public.meals;
drop policy if exists meals_insert_own on public.meals;
drop policy if exists meals_update_own on public.meals;
drop policy if exists meals_delete_own on public.meals;

create policy meals_select_own
  on public.meals
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.diets
      where diets.id = meals.diet_id
        and diets.user_id = auth.uid()
    )
  );

create policy meals_insert_own
  on public.meals
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.diets
      where diets.id = meals.diet_id
        and diets.user_id = auth.uid()
    )
  );

create policy meals_update_own
  on public.meals
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.diets
      where diets.id = meals.diet_id
        and diets.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.diets
      where diets.id = meals.diet_id
        and diets.user_id = auth.uid()
    )
  );

create policy meals_delete_own
  on public.meals
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.diets
      where diets.id = meals.diet_id
        and diets.user_id = auth.uid()
    )
  );

drop policy if exists daily_diets_select_own on public.daily_diets;
drop policy if exists daily_diets_insert_own on public.daily_diets;
drop policy if exists daily_diets_update_own on public.daily_diets;
drop policy if exists daily_diets_delete_own on public.daily_diets;
drop policy if exists pending_assignments_no_direct_access on public.pending_user_assignments;

create policy daily_diets_select_own
  on public.daily_diets
  for select
  to authenticated
  using (user_id = auth.uid());

create policy daily_diets_insert_own
  on public.daily_diets
  for insert
  to authenticated
  with check (user_id = auth.uid());

create policy daily_diets_update_own
  on public.daily_diets
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy daily_diets_delete_own
  on public.daily_diets
  for delete
  to authenticated
  using (user_id = auth.uid());

create policy pending_assignments_no_direct_access
  on public.pending_user_assignments
  for all
  to authenticated
  using (false)
  with check (false);

-- Fuerza a PostgREST/Supabase API a recargar la cache del esquema.
notify pgrst, 'reload schema';

commit;

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if current_user_id is null then
    raise exception 'No autenticado';
  end if;

  delete from public.daily_diets
  where user_id = current_user_id;

  delete from public.exercises
  using public.workouts
  where public.exercises.workout_id::text = public.workouts.id::text
    and public.workouts.user_id = current_user_id;

  delete from public.meals
  using public.diets
  where public.meals.diet_id::text = public.diets.id::text
    and public.diets.user_id = current_user_id;

  delete from public.workouts
  where user_id = current_user_id;

  delete from public.diets
  where user_id = current_user_id;

  delete from auth.sessions
  where user_id = current_user_id;

  delete from auth.identities
  where user_id = current_user_id;

  delete from auth.users
  where id = current_user_id;
end;
$$;

drop function if exists public.assign_workout_to_email(text, jsonb);
drop function if exists public.assign_diet_to_email(text, jsonb);
drop function if exists public.claim_pending_assignments();

create or replace function public.assign_workout_to_email(
  target_email text,
  workout_payload jsonb
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_user_id uuid;
  new_workout_id public.workouts.id%type;
begin
  if current_user_id is null then
    raise exception 'No autenticado';
  end if;

  if not exists (
    select 1
    from auth.users
    where id = current_user_id
      and raw_user_meta_data->>'role' = 'admin'
  ) then
    raise exception 'Solo admins pueden asignar rutinas';
  end if;

  select id
    into target_user_id
  from auth.users
  where lower(email) = lower(trim(target_email))
  limit 1;

  if target_user_id is null then
    insert into public.pending_user_assignments (
      target_email,
      assignment_type,
      payload,
      assigned_by
    )
    values (
      lower(trim(target_email)),
      'workout',
      workout_payload,
      current_user_id
    );

    return 'pending:' || lower(trim(target_email));
  end if;

  insert into public.workouts (user_id, name, day_of_week)
  values (
    target_user_id,
    coalesce(nullif(workout_payload->>'name', ''), 'Rutina asignada'),
    coalesce((workout_payload->>'day_of_week')::integer, 1)
  )
  returning id into new_workout_id;

  insert into public.exercises (
    workout_id,
    name,
    sets,
    reps,
    rest_seconds,
    exercise_order,
    notes
  )
  select
    new_workout_id,
    coalesce(nullif(exercise->>'name', ''), 'Ejercicio'),
    coalesce((exercise->>'sets')::integer, 0),
    coalesce(nullif(exercise->>'reps', ''), '-'),
    coalesce((exercise->>'rest_seconds')::integer, 0),
    coalesce((exercise->>'exercise_order')::integer, 0),
    coalesce(exercise->>'notes', '')
  from jsonb_array_elements(
    coalesce(workout_payload->'exercises', '[]'::jsonb)
  ) as exercise;

  return new_workout_id::text;
end;
$$;

create or replace function public.assign_diet_to_email(
  target_email text,
  diet_payload jsonb
)
returns text
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  target_user_id uuid;
  new_diet_id public.diets.id%type;
begin
  if current_user_id is null then
    raise exception 'No autenticado';
  end if;

  if not exists (
    select 1
    from auth.users
    where id = current_user_id
      and raw_user_meta_data->>'role' = 'admin'
  ) then
    raise exception 'Solo admins pueden asignar dietas';
  end if;

  select id
    into target_user_id
  from auth.users
  where lower(email) = lower(trim(target_email))
  limit 1;

  if target_user_id is null then
    insert into public.pending_user_assignments (
      target_email,
      assignment_type,
      payload,
      assigned_by
    )
    values (
      lower(trim(target_email)),
      'diet',
      diet_payload,
      current_user_id
    );

    return 'pending:' || lower(trim(target_email));
  end if;

  insert into public.diets (user_id, name, day_of_week)
  values (
    target_user_id,
    coalesce(nullif(diet_payload->>'name', ''), 'Dieta asignada'),
    coalesce((diet_payload->>'day_of_week')::integer, 1)
  )
  returning id into new_diet_id;

  insert into public.meals (
    diet_id,
    name,
    calories,
    protein,
    carbs,
    fats,
    notes
  )
  select
    new_diet_id,
    coalesce(nullif(meal->>'name', ''), 'Comida'),
    coalesce((meal->>'calories')::integer, 0),
    coalesce((meal->>'protein')::integer, 0),
    coalesce((meal->>'carbs')::integer, 0),
    coalesce((meal->>'fats')::integer, 0),
    coalesce(meal->>'notes', '')
  from jsonb_array_elements(
    coalesce(diet_payload->'meals', '[]'::jsonb)
  ) as meal;

  return new_diet_id::text;
end;
$$;

create or replace function public.claim_pending_assignments()
returns integer
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_user_id uuid := auth.uid();
  current_email text;
  assignment record;
  new_workout_id public.workouts.id%type;
  new_diet_id public.diets.id%type;
  claimed_count integer := 0;
begin
  if current_user_id is null then
    raise exception 'No autenticado';
  end if;

  select lower(email)
    into current_email
  from auth.users
  where id = current_user_id;

  for assignment in
    select *
    from public.pending_user_assignments
    where lower(target_email) = current_email
    order by created_at asc
  loop
    if assignment.assignment_type = 'workout' then
      insert into public.workouts (user_id, name, day_of_week)
      values (
        current_user_id,
        coalesce(nullif(assignment.payload->>'name', ''), 'Rutina asignada'),
        coalesce((assignment.payload->>'day_of_week')::integer, 1)
      )
      returning id into new_workout_id;

      insert into public.exercises (
        workout_id,
        name,
        sets,
        reps,
        rest_seconds,
        exercise_order,
        notes
      )
      select
        new_workout_id,
        coalesce(nullif(exercise->>'name', ''), 'Ejercicio'),
        coalesce((exercise->>'sets')::integer, 0),
        coalesce(nullif(exercise->>'reps', ''), '-'),
        coalesce((exercise->>'rest_seconds')::integer, 0),
        coalesce((exercise->>'exercise_order')::integer, 0),
        coalesce(exercise->>'notes', '')
      from jsonb_array_elements(
        coalesce(assignment.payload->'exercises', '[]'::jsonb)
      ) as exercise;
    elsif assignment.assignment_type = 'diet' then
      insert into public.diets (user_id, name, day_of_week)
      values (
        current_user_id,
        coalesce(nullif(assignment.payload->>'name', ''), 'Dieta asignada'),
        coalesce((assignment.payload->>'day_of_week')::integer, 1)
      )
      returning id into new_diet_id;

      insert into public.meals (
        diet_id,
        name,
        calories,
        protein,
        carbs,
        fats,
        notes
      )
      select
        new_diet_id,
        coalesce(nullif(meal->>'name', ''), 'Comida'),
        coalesce((meal->>'calories')::integer, 0),
        coalesce((meal->>'protein')::integer, 0),
        coalesce((meal->>'carbs')::integer, 0),
        coalesce((meal->>'fats')::integer, 0),
        coalesce(meal->>'notes', '')
      from jsonb_array_elements(
        coalesce(assignment.payload->'meals', '[]'::jsonb)
      ) as meal;
    end if;

    delete from public.pending_user_assignments
    where id = assignment.id;
    claimed_count := claimed_count + 1;
  end loop;

  return claimed_count;
end;
$$;

revoke all on function public.delete_own_account() from public;
revoke all on function public.assign_workout_to_email(text, jsonb) from public;
revoke all on function public.assign_diet_to_email(text, jsonb) from public;
revoke all on function public.claim_pending_assignments() from public;

grant execute on function public.delete_own_account() to authenticated;
grant execute on function public.assign_workout_to_email(text, jsonb) to authenticated;
grant execute on function public.assign_diet_to_email(text, jsonb) to authenticated;
grant execute on function public.claim_pending_assignments() to authenticated;

notify pgrst, 'reload schema';
