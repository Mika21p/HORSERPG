-- HorseRPG v0.4-C Race Results database layer.
-- Winning Post remains the source of actual race facts. This migration records
-- GM-authoritative actual races and results without creating any prize, ledger,
-- condition, injury, retirement, UI, or Realtime side effects.

begin;

create type public.race_result_status as enum ('CONFIRMED', 'VOIDED');

-- One row is one race that actually occurred in Winning Post. Catalog facts are
-- copied into race_name / grade so later catalog edits cannot rewrite history.
create table public.actual_races (
  id uuid primary key default gen_random_uuid(),
  wp_year integer not null check (wp_year > 0),
  wp_month smallint not null check (wp_month between 1 and 12),
  wp_week smallint not null check (wp_week between 1 and 5),
  race_kind public.race_entry_race_kind not null,
  race_catalog_id uuid references public.race_catalog(id) on delete restrict,
  race_name text not null check (length(btrim(race_name)) > 0),
  grade public.race_catalog_grade,
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint actual_races_identity_check check (
    (
      race_kind = 'CATALOG'::public.race_entry_race_kind
      and race_catalog_id is not null
      and grade is not null
    )
    or
    (
      race_kind in (
        'MAIDEN'::public.race_entry_race_kind,
        'CONDITION'::public.race_entry_race_kind,
        'OTHER'::public.race_entry_race_kind
      )
      and race_catalog_id is null
      and grade is null
    )
  )
);

create unique index actual_races_one_catalog_per_wp_week_idx
  on public.actual_races (wp_year, wp_month, wp_week, race_catalog_id)
  where race_kind = 'CATALOG'::public.race_entry_race_kind;

create index actual_races_wp_time_idx
  on public.actual_races (wp_year, wp_month, wp_week);

-- A result always derives Horse identity from its confirmed pre-race entry.
-- A VOIDED row is retained forever; only current CONFIRMED rows participate in
-- result uniqueness and the public projection.
create table public.race_results (
  id uuid primary key default gen_random_uuid(),
  confirmed_race_entry_id uuid not null references public.confirmed_race_entries(id) on delete restrict,
  actual_race_id uuid not null references public.actual_races(id) on delete restrict,
  horse_id uuid not null references public.horses(id) on delete restrict,
  status public.race_result_status not null default 'CONFIRMED'::public.race_result_status,
  finish_position smallint not null check (finish_position between 1 and 99),
  prize_amount bigint not null check (prize_amount >= 0),
  actual_jockey text check (actual_jockey is null or length(btrim(actual_jockey)) > 0),
  actual_running_style text check (actual_running_style is null or length(btrim(actual_running_style)) > 0),
  gm_note text,
  recorded_by_user_id uuid references auth.users(id) on delete set null,
  recorded_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  voided_by_user_id uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  constraint race_results_void_state_check check (
    (
      status = 'CONFIRMED'::public.race_result_status
      and voided_by_user_id is null
      and voided_at is null
      and void_reason is null
    )
    or
    (
      status = 'VOIDED'::public.race_result_status
      and voided_at is not null
      and void_reason is not null
      and length(btrim(void_reason)) > 0
    )
  )
);

create unique index race_results_one_confirmed_result_per_entry_idx
  on public.race_results (confirmed_race_entry_id)
  where status = 'CONFIRMED'::public.race_result_status;

create unique index race_results_one_confirmed_result_per_horse_actual_race_idx
  on public.race_results (actual_race_id, horse_id)
  where status = 'CONFIRMED'::public.race_result_status;

create index race_results_actual_race_id_idx on public.race_results (actual_race_id);
create index race_results_horse_id_recorded_at_idx on public.race_results (horse_id, recorded_at desc);

create trigger actual_races_set_updated_at
before update on public.actual_races
for each row execute function public.set_updated_at();

create trigger race_results_set_updated_at
before update on public.race_results
for each row execute function public.set_updated_at();

-- Future server paths cannot disconnect a result from its entry Horse or move
-- it onto another entry. Correction may change only the actual result facts.
create function public.enforce_race_result_entry_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_entry_horse_id uuid;
begin
  if tg_op = 'UPDATE'
    and (
      new.confirmed_race_entry_id is distinct from old.confirmed_race_entry_id
      or new.horse_id is distinct from old.horse_id
    ) then
    raise exception 'a race result cannot be moved to another confirmed entry or Horse; void and re-record it instead'
      using errcode = '23514';
  end if;

  select horse_id
  into v_entry_horse_id
  from public.confirmed_race_entries
  where id = new.confirmed_race_entry_id
  for key share;

  if not found or v_entry_horse_id <> new.horse_id then
    raise exception 'race result Horse must equal the Horse of its confirmed race entry'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger race_results_enforce_entry_integrity
before insert or update of confirmed_race_entry_id, horse_id on public.race_results
for each row execute function public.enforce_race_result_entry_integrity();

-- Actual race time is historical-or-current only. The locked singleton avoids
-- racing a GM game-clock update while a result is being recorded or corrected.
create function public.assert_actual_race_wp_time_not_future(
  p_wp_year integer,
  p_wp_month smallint,
  p_wp_week smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game_state public.game_state%rowtype;
begin
  if p_wp_year is null or p_wp_year <= 0
    or p_wp_month is null or p_wp_month not between 1 and 12
    or p_wp_week is null or p_wp_week not between 1 and 5 then
    raise exception 'actual-race WP time is invalid'
      using errcode = '23514';
  end if;

  select *
  into v_game_state
  from public.game_state
  for share;

  if not found then
    raise exception 'game state must be initialized before actual races can be recorded'
      using errcode = '23514';
  end if;

  if (p_wp_year, p_wp_month, p_wp_week)
    > (v_game_state.current_wp_year, v_game_state.current_wp_month, v_game_state.current_wp_week) then
    raise exception 'actual-race WP time cannot be later than the current game week'
      using errcode = '23514';
  end if;
end;
$$;

-- This helper intentionally permits an inactive catalog for historical race
-- entry, but still requires the referenced row and snapshots its current facts.
create function public.resolve_actual_race_identity(
  p_race_kind public.race_entry_race_kind,
  p_race_catalog_id uuid,
  p_race_label text
)
returns table (
  race_catalog_id uuid,
  race_name text,
  grade public.race_catalog_grade
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_catalog public.race_catalog%rowtype;
  v_label text;
begin
  v_label := nullif(btrim(p_race_label), '');

  if p_race_kind is null then
    raise exception 'actual-race race kind is required'
      using errcode = '23514';
  end if;

  if p_race_kind = 'CATALOG'::public.race_entry_race_kind then
    if p_race_catalog_id is null or v_label is not null then
      raise exception 'a catalog actual race requires a catalog reference and no free-text label'
        using errcode = '23514';
    end if;

    select *
    into v_catalog
    from public.race_catalog
    where id = p_race_catalog_id
    for key share;

    if not found then
      raise exception 'selected race catalog entry does not exist'
        using errcode = '23503';
    end if;

    return query select v_catalog.id, v_catalog.name, v_catalog.grade;
    return;
  end if;

  if p_race_kind not in (
    'MAIDEN'::public.race_entry_race_kind,
    'CONDITION'::public.race_entry_race_kind,
    'OTHER'::public.race_entry_race_kind
  ) or p_race_catalog_id is not null or v_label is null then
    raise exception 'a non-catalog actual race requires a free-text race label and no catalog reference'
      using errcode = '23514';
  end if;

  return query select null::uuid, v_label, null::public.race_catalog_grade;
end;
$$;

create function public.actual_race_audit_data(p_actual_race public.actual_races)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_actual_race.id,
    'wp_year', p_actual_race.wp_year,
    'wp_month', p_actual_race.wp_month,
    'wp_week', p_actual_race.wp_week,
    'race_kind', p_actual_race.race_kind,
    'race_catalog_id', p_actual_race.race_catalog_id,
    'race_name', p_actual_race.race_name,
    'grade', p_actual_race.grade
  );
$$;

create function public.race_result_audit_data(p_race_result public.race_results)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_race_result.id,
    'confirmed_race_entry_id', p_race_result.confirmed_race_entry_id,
    'actual_race_id', p_race_result.actual_race_id,
    'horse_id', p_race_result.horse_id,
    'status', p_race_result.status,
    'finish_position', p_race_result.finish_position,
    'prize_amount', p_race_result.prize_amount,
    'actual_jockey', p_race_result.actual_jockey,
    'actual_running_style', p_race_result.actual_running_style,
    'gm_note', p_race_result.gm_note,
    'voided_at', p_race_result.voided_at,
    'void_reason', p_race_result.void_reason
  );
$$;

create function public.assert_race_result_facts(
  p_finish_position smallint,
  p_prize_amount bigint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_finish_position is null or p_finish_position not between 1 and 99 then
    raise exception 'race result finish position must be between 1 and 99'
      using errcode = '23514';
  end if;

  if p_prize_amount is null or p_prize_amount < 0 then
    raise exception 'race result prize amount must be zero or greater'
      using errcode = '23514';
  end if;
end;
$$;

create function public.create_actual_race(
  p_wp_year integer,
  p_wp_month smallint,
  p_wp_week smallint,
  p_race_kind public.race_entry_race_kind,
  p_race_catalog_id uuid,
  p_race_label text default null
)
returns public.actual_races
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity record;
  v_actual_race public.actual_races%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create an actual race'
      using errcode = '42501';
  end if;

  perform public.assert_actual_race_wp_time_not_future(p_wp_year, p_wp_month, p_wp_week);
  select * into v_identity
  from public.resolve_actual_race_identity(p_race_kind, p_race_catalog_id, p_race_label);

  insert into public.actual_races (
    wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_name, grade,
    created_by_user_id
  ) values (
    p_wp_year, p_wp_month, p_wp_week, p_race_kind, v_identity.race_catalog_id,
    v_identity.race_name, v_identity.grade, auth.uid()
  ) returning * into v_actual_race;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'ACTUAL_RACE_CREATED', 'actual_races',
    v_actual_race.id::text, public.actual_race_audit_data(v_actual_race)
  );

  return v_actual_race;
end;
$$;

create function public.correct_actual_race(
  p_actual_race_id uuid,
  p_wp_year integer,
  p_wp_month smallint,
  p_wp_week smallint,
  p_race_kind public.race_entry_race_kind,
  p_race_catalog_id uuid,
  p_race_label text,
  p_reason text
)
returns public.actual_races
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actual_race public.actual_races%rowtype;
  v_identity record;
  v_reason text;
  v_before_data jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may correct an actual race'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then
    raise exception 'actual-race correction reason is required'
      using errcode = '23514';
  end if;

  select *
  into v_actual_race
  from public.actual_races
  where id = p_actual_race_id
  for update;

  if not found then
    raise exception 'actual race does not exist'
      using errcode = '23503';
  end if;

  perform public.assert_actual_race_wp_time_not_future(p_wp_year, p_wp_month, p_wp_week);
  select * into v_identity
  from public.resolve_actual_race_identity(p_race_kind, p_race_catalog_id, p_race_label);
  v_before_data := public.actual_race_audit_data(v_actual_race);

  update public.actual_races
  set wp_year = p_wp_year,
      wp_month = p_wp_month,
      wp_week = p_wp_week,
      race_kind = p_race_kind,
      race_catalog_id = v_identity.race_catalog_id,
      race_name = v_identity.race_name,
      grade = v_identity.grade
  where id = v_actual_race.id
  returning * into v_actual_race;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'ACTUAL_RACE_CORRECTED', 'actual_races',
    v_actual_race.id::text, v_before_data, public.actual_race_audit_data(v_actual_race), v_reason
  );

  return v_actual_race;
end;
$$;

create function public.record_race_result(
  p_confirmed_race_entry_id uuid,
  p_actual_race_id uuid,
  p_finish_position smallint,
  p_prize_amount bigint,
  p_actual_jockey text default null,
  p_actual_running_style text default null,
  p_gm_note text default null
)
returns public.race_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry public.confirmed_race_entries%rowtype;
  v_actual_race public.actual_races%rowtype;
  v_existing public.race_results%rowtype;
  v_result public.race_results%rowtype;
  v_actual_jockey text;
  v_actual_running_style text;
  v_gm_note text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may record a race result'
      using errcode = '42501';
  end if;

  v_actual_jockey := nullif(btrim(p_actual_jockey), '');
  v_actual_running_style := nullif(btrim(p_actual_running_style), '');
  v_gm_note := nullif(btrim(p_gm_note), '');

  -- The confirmed Entry serializes all Record attempts for that Entry. Check a
  -- current result before re-validating any mutable world state so an exact
  -- retry remains idempotent after, for example, a later game-clock correction.
  select *
  into v_entry
  from public.confirmed_race_entries
  where id = p_confirmed_race_entry_id
  for update;

  if not found then
    raise exception 'confirmed race entry does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_existing
  from public.race_results
  where confirmed_race_entry_id = v_entry.id
    and status = 'CONFIRMED'::public.race_result_status
  for update;

  if found then
    if v_existing.actual_race_id = p_actual_race_id
      and v_existing.finish_position = p_finish_position
      and v_existing.prize_amount = p_prize_amount
      and v_existing.actual_jockey is not distinct from v_actual_jockey
      and v_existing.actual_running_style is not distinct from v_actual_running_style
      and v_existing.gm_note is not distinct from v_gm_note then
      return v_existing;
    end if;

    raise exception 'race result already exists with different facts; use correction flow'
      using errcode = 'P0001';
  end if;

  select *
  into v_actual_race
  from public.actual_races
  where id = p_actual_race_id
  for key share;

  if not found then
    raise exception 'actual race does not exist'
      using errcode = '23503';
  end if;

  perform public.assert_actual_race_wp_time_not_future(
    v_actual_race.wp_year, v_actual_race.wp_month, v_actual_race.wp_week
  );
  perform public.assert_race_result_facts(p_finish_position, p_prize_amount);

  insert into public.race_results (
    confirmed_race_entry_id, actual_race_id, horse_id, finish_position, prize_amount,
    actual_jockey, actual_running_style, gm_note, recorded_by_user_id
  ) values (
    v_entry.id, v_actual_race.id, v_entry.horse_id, p_finish_position, p_prize_amount,
    v_actual_jockey, v_actual_running_style, v_gm_note, auth.uid()
  ) returning * into v_result;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_RESULT_RECORDED', 'race_results',
    v_result.id::text, public.race_result_audit_data(v_result)
  );

  return v_result;
end;
$$;

create function public.correct_race_result(
  p_race_result_id uuid,
  p_actual_race_id uuid,
  p_finish_position smallint,
  p_prize_amount bigint,
  p_actual_jockey text,
  p_actual_running_style text,
  p_gm_note text,
  p_reason text
)
returns public.race_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.race_results%rowtype;
  v_actual_race public.actual_races%rowtype;
  v_actual_jockey text;
  v_actual_running_style text;
  v_gm_note text;
  v_reason text;
  v_before_data jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may correct a race result'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then
    raise exception 'race-result correction reason is required'
      using errcode = '23514';
  end if;

  select *
  into v_result
  from public.race_results
  where id = p_race_result_id
  for update;

  if not found then
    raise exception 'race result does not exist'
      using errcode = '23503';
  end if;

  if v_result.status <> 'CONFIRMED'::public.race_result_status then
    raise exception 'only a confirmed race result may be corrected'
      using errcode = '23514';
  end if;

  select *
  into v_actual_race
  from public.actual_races
  where id = p_actual_race_id
  for key share;

  if not found then
    raise exception 'actual race does not exist'
      using errcode = '23503';
  end if;

  perform public.assert_actual_race_wp_time_not_future(
    v_actual_race.wp_year, v_actual_race.wp_month, v_actual_race.wp_week
  );
  perform public.assert_race_result_facts(p_finish_position, p_prize_amount);

  v_actual_jockey := nullif(btrim(p_actual_jockey), '');
  v_actual_running_style := nullif(btrim(p_actual_running_style), '');
  v_gm_note := nullif(btrim(p_gm_note), '');
  v_before_data := public.race_result_audit_data(v_result);

  update public.race_results
  set actual_race_id = v_actual_race.id,
      finish_position = p_finish_position,
      prize_amount = p_prize_amount,
      actual_jockey = v_actual_jockey,
      actual_running_style = v_actual_running_style,
      gm_note = v_gm_note
  where id = v_result.id
  returning * into v_result;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_RESULT_CORRECTED', 'race_results',
    v_result.id::text, v_before_data, public.race_result_audit_data(v_result), v_reason
  );

  return v_result;
end;
$$;

create function public.void_race_result(
  p_race_result_id uuid,
  p_reason text
)
returns public.race_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.race_results%rowtype;
  v_reason text;
  v_before_data jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may void a race result'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then
    raise exception 'race-result void reason is required'
      using errcode = '23514';
  end if;

  select *
  into v_result
  from public.race_results
  where id = p_race_result_id
  for update;

  if not found then
    raise exception 'race result does not exist'
      using errcode = '23503';
  end if;

  if v_result.status = 'VOIDED'::public.race_result_status then
    if v_result.void_reason is distinct from v_reason then
      raise exception 'a voided race result cannot have its void reason changed'
        using errcode = '23514';
    end if;

    return v_result;
  end if;

  v_before_data := public.race_result_audit_data(v_result);

  update public.race_results
  set status = 'VOIDED'::public.race_result_status,
      voided_by_user_id = auth.uid(),
      voided_at = clock_timestamp(),
      void_reason = v_reason
  where id = v_result.id
  returning * into v_result;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_RESULT_VOIDED', 'race_results',
    v_result.id::text, v_before_data, public.race_result_audit_data(v_result), v_reason
  );

  return v_result;
end;
$$;

alter table public.actual_races enable row level security;
alter table public.race_results enable row level security;

create policy actual_races_select_gm
on public.actual_races
for select to authenticated
using (public.is_current_user_gm());

create policy race_results_select_gm
on public.race_results
for select to authenticated
using (public.is_current_user_gm());

-- The view is intentionally owner-executed: authenticated PLAYER users get
-- only current public facts while the base tables remain GM-only under RLS.
create view public.race_results_public
with (security_barrier = true)
as
select
  result.id as race_result_id,
  result.confirmed_race_entry_id,
  result.actual_race_id,
  result.horse_id,
  entry.owner_id,
  actual_race.wp_year,
  actual_race.wp_month,
  actual_race.wp_week,
  actual_race.race_kind,
  actual_race.race_catalog_id,
  actual_race.race_name,
  actual_race.grade,
  result.finish_position,
  result.prize_amount,
  result.actual_jockey,
  result.actual_running_style,
  result.recorded_at
from public.race_results as result
join public.actual_races as actual_race on actual_race.id = result.actual_race_id
join public.confirmed_race_entries as entry on entry.id = result.confirmed_race_entry_id
where result.status = 'CONFIRMED'::public.race_result_status;

revoke all on table public.actual_races from public, anon, authenticated, service_role;
revoke all on table public.race_results from public, anon, authenticated, service_role;
revoke all on table public.race_results_public from public, anon, authenticated, service_role;

grant select on table public.actual_races, public.race_results to authenticated;
grant select on table public.race_results_public to authenticated;

revoke all on function public.enforce_race_result_entry_integrity() from public, anon, authenticated, service_role;
revoke all on function public.assert_actual_race_wp_time_not_future(integer, smallint, smallint) from public, anon, authenticated, service_role;
revoke all on function public.resolve_actual_race_identity(public.race_entry_race_kind, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.actual_race_audit_data(public.actual_races) from public, anon, authenticated, service_role;
revoke all on function public.race_result_audit_data(public.race_results) from public, anon, authenticated, service_role;
revoke all on function public.assert_race_result_facts(smallint, bigint) from public, anon, authenticated, service_role;
revoke all on function public.create_actual_race(integer, smallint, smallint, public.race_entry_race_kind, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.correct_actual_race(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function public.record_race_result(uuid, uuid, smallint, bigint, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.correct_race_result(uuid, uuid, smallint, bigint, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.void_race_result(uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.create_actual_race(integer, smallint, smallint, public.race_entry_race_kind, uuid, text) to authenticated;
grant execute on function public.correct_actual_race(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text) to authenticated;
grant execute on function public.record_race_result(uuid, uuid, smallint, bigint, text, text, text) to authenticated;
grant execute on function public.correct_race_result(uuid, uuid, smallint, bigint, text, text, text, text) to authenticated;
grant execute on function public.void_race_result(uuid, text) to authenticated;

comment on table public.actual_races is
  'GM-recorded Winning Post actual race facts. Catalog name and grade are immutable historical snapshots, not live catalog display values.';
comment on table public.race_results is
  'GM-recorded Horse post-race facts. prize_amount is only a Winning Post result fact in v0.4-C and must not create financial transactions or prize receivables.';
comment on view public.race_results_public is
  'Authenticated public projection of current confirmed race results. It excludes GM notes, actor identities, void data, and all VOIDED history.';

commit;
