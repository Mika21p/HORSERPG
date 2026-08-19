-- HorseRPG v0.4-A Race Management database layer.
-- This migration records Race Catalog references, PLAYER race-entry intent,
-- and GM-authoritative confirmed schedules. It deliberately excludes actual
-- results, prizes, condition resolution, post-race injuries, and UI work.

begin;

create type public.race_catalog_grade as enum ('OP', 'G3', 'G2', 'G1');

create type public.race_entry_race_kind as enum (
  'CATALOG',
  'MAIDEN',
  'CONDITION',
  'OTHER'
);

create type public.race_entry_request_status as enum (
  'PENDING',
  'CONFIRMED',
  'REJECTED',
  'WITHDRAWN'
);

-- A catalog Race supplies a selectable reference and default month/week only.
-- It must never constrain the final WP time stored on a confirmed schedule.
create table public.race_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null unique check (length(btrim(name)) > 0),
  grade public.race_catalog_grade not null,
  default_wp_month smallint not null check (default_wp_month between 1 and 12),
  default_wp_week smallint not null check (default_wp_week between 1 and 5),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- This table is immutable PLAYER intent plus its review state. The requested
-- facts are never overwritten when a GM chooses different final facts.
create table public.race_entry_requests (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  requested_by_user_id uuid references auth.users(id) on delete set null,
  requested_wp_year integer not null check (requested_wp_year > 0),
  requested_wp_month smallint not null check (requested_wp_month between 1 and 12),
  requested_wp_week smallint not null check (requested_wp_week between 1 and 5),
  requested_race_kind public.race_entry_race_kind not null,
  requested_race_catalog_id uuid references public.race_catalog(id) on delete restrict,
  requested_race_label text,
  requested_jockey text check (requested_jockey is null or length(btrim(requested_jockey)) > 0),
  requested_running_style text check (requested_running_style is null or length(btrim(requested_running_style)) > 0),
  player_note text,
  status public.race_entry_request_status not null default 'PENDING'::public.race_entry_request_status,
  reviewed_by_user_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  rejection_reason text,
  withdrawn_by_user_id uuid references auth.users(id) on delete set null,
  withdrawn_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint race_entry_requests_race_identity_check check (
    (
      requested_race_kind = 'CATALOG'::public.race_entry_race_kind
      and requested_race_catalog_id is not null
      and requested_race_label is null
    )
    or
    (
      requested_race_kind in (
        'MAIDEN'::public.race_entry_race_kind,
        'CONDITION'::public.race_entry_race_kind,
        'OTHER'::public.race_entry_race_kind
      )
      and requested_race_catalog_id is null
      and requested_race_label is not null
      and length(btrim(requested_race_label)) > 0
    )
  ),
  constraint race_entry_requests_status_resolution_check check (
    (
      status = 'PENDING'::public.race_entry_request_status
      and reviewed_by_user_id is null
      and reviewed_at is null
      and rejection_reason is null
      and withdrawn_by_user_id is null
      and withdrawn_at is null
    )
    or
    (
      status = 'CONFIRMED'::public.race_entry_request_status
      and reviewed_at is not null
      and rejection_reason is null
      and withdrawn_by_user_id is null
      and withdrawn_at is null
    )
    or
    (
      status = 'REJECTED'::public.race_entry_request_status
      and reviewed_at is not null
      and withdrawn_by_user_id is null
      and withdrawn_at is null
    )
    or
    (
      status = 'WITHDRAWN'::public.race_entry_request_status
      and reviewed_by_user_id is null
      and reviewed_at is null
      and rejection_reason is null
      and withdrawn_at is not null
    )
  )
);

create index race_entry_requests_owner_status_idx
  on public.race_entry_requests (owner_id, status, created_at desc);
create index race_entry_requests_horse_status_idx
  on public.race_entry_requests (horse_id, status, requested_wp_year, requested_wp_month, requested_wp_week);

-- A confirmed entry is the authoritative pre-race schedule and provides a
-- stable future FK target for race_results. It is intentionally separate from
-- the request that originally proposed the participation.
create table public.confirmed_race_entries (
  id uuid primary key default gen_random_uuid(),
  -- A GM may authoritatively schedule an eligible Horse without a preceding
  -- PLAYER request. PostgreSQL UNIQUE permits multiple NULLs, while still
  -- enforcing the one-to-one link whenever a request is present.
  request_id uuid unique references public.race_entry_requests(id) on delete restrict,
  horse_id uuid not null references public.horses(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  wp_year integer not null check (wp_year > 0),
  wp_month smallint not null check (wp_month between 1 and 12),
  wp_week smallint not null check (wp_week between 1 and 5),
  race_kind public.race_entry_race_kind not null,
  race_catalog_id uuid references public.race_catalog(id) on delete restrict,
  race_label text,
  jockey text check (jockey is null or length(btrim(jockey)) > 0),
  running_style text check (running_style is null or length(btrim(running_style)) > 0),
  gm_note text,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default now(),
  constraint confirmed_race_entries_race_identity_check check (
    (
      race_kind = 'CATALOG'::public.race_entry_race_kind
      and race_catalog_id is not null
      and race_label is null
    )
    or
    (
      race_kind in (
        'MAIDEN'::public.race_entry_race_kind,
        'CONDITION'::public.race_entry_race_kind,
        'OTHER'::public.race_entry_race_kind
      )
      and race_catalog_id is null
      and race_label is not null
      and length(btrim(race_label)) > 0
    )
  ),
  constraint confirmed_race_entries_one_horse_per_wp_week unique (
    horse_id, wp_year, wp_month, wp_week
  )
);

create index confirmed_race_entries_owner_wp_time_idx
  on public.confirmed_race_entries (owner_id, wp_year, wp_month, wp_week);
create index confirmed_race_entries_race_catalog_id_idx
  on public.confirmed_race_entries (race_catalog_id)
  where race_catalog_id is not null;

create trigger race_catalog_set_updated_at
before update on public.race_catalog
for each row execute function public.set_updated_at();

create trigger race_entry_requests_set_updated_at
before update on public.race_entry_requests
for each row execute function public.set_updated_at();

-- Keep the request/confirmed-entry association structurally meaningful even
-- if future server code is added. A NULL request_id is allowed exclusively for
-- the GM-only direct scheduling RPC, which marks the current transaction
-- immediately before its insert. A request-backed entry is inserted while the
-- request is still PENDING, then that request changes to CONFIRMED in the same
-- transaction.
create function public.enforce_confirmed_race_entry_request_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_request_horse_id uuid;
  v_request_owner_id uuid;
  v_request_status public.race_entry_request_status;
begin
  if new.request_id is null then
    if auth.uid() is null
      or not public.is_current_user_gm()
      or new.confirmed_by_user_id is distinct from auth.uid()
      or current_setting('horserpg.gm_direct_race_entry', true) is distinct from 'on' then
      raise exception 'a request-less confirmed race entry must use the controlled GM direct-entry path'
        using errcode = '42501';
    end if;

    return new;
  end if;

  select horse_id, owner_id, status
  into v_request_horse_id, v_request_owner_id, v_request_status
  from public.race_entry_requests
  where id = new.request_id
  for key share;

  if not found
    or v_request_horse_id <> new.horse_id
    or v_request_owner_id <> new.owner_id
    or v_request_status <> 'PENDING'::public.race_entry_request_status then
    raise exception 'a confirmed race entry must match one pending race-entry request'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger confirmed_race_entries_enforce_request_integrity
before insert on public.confirmed_race_entries
for each row execute function public.enforce_confirmed_race_entry_request_integrity();

-- Prevent request status from drifting away from the authoritative schedule.
-- The normal confirm RPC deliberately inserts its entry first, then updates
-- the request, so this reverse check also protects future server paths.
create function public.enforce_race_entry_request_resolution_integrity()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_entry_count integer;
  v_entry_horse_id uuid;
  v_entry_owner_id uuid;
begin
  if new.status = 'CONFIRMED'::public.race_entry_request_status then
    select count(*)
    into v_entry_count
    from public.confirmed_race_entries
    where request_id = new.id;

    if v_entry_count <> 1 then
      raise exception 'a CONFIRMED race-entry request must have exactly one matching confirmed race entry'
        using errcode = '23514';
    end if;

    select horse_id, owner_id
    into v_entry_horse_id, v_entry_owner_id
    from public.confirmed_race_entries
    where request_id = new.id;

    if v_entry_horse_id <> new.horse_id or v_entry_owner_id <> new.owner_id then
      raise exception 'a CONFIRMED race-entry request must have exactly one matching confirmed race entry'
        using errcode = '23514';
    end if;
  elsif new.status in (
    'REJECTED'::public.race_entry_request_status,
    'WITHDRAWN'::public.race_entry_request_status
  ) and exists (
    select 1
    from public.confirmed_race_entries
    where request_id = new.id
  ) then
    raise exception 'a rejected or withdrawn race-entry request cannot have a confirmed race entry'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger race_entry_requests_enforce_resolution_integrity
before update of status on public.race_entry_requests
for each row execute function public.enforce_race_entry_request_resolution_integrity();

-- Internal validation is shared by submit and confirm, and intentionally has
-- no client EXECUTE grant. The game state is locked while a final time is
-- checked so a concurrent week advance cannot race a confirmation.
create function public.assert_race_entry_wp_time_not_past(
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
    raise exception 'race-entry WP time is invalid'
      using errcode = '23514';
  end if;

  select *
  into v_game_state
  from public.game_state
  for share;

  if not found then
    raise exception 'game state must be initialized before race entries can be scheduled'
      using errcode = '23514';
  end if;

  if (p_wp_year, p_wp_month, p_wp_week)
    < (v_game_state.current_wp_year, v_game_state.current_wp_month, v_game_state.current_wp_week) then
    raise exception 'race-entry WP time cannot be earlier than the current game week'
      using errcode = '23514';
  end if;
end;
$$;

create function public.assert_race_entry_identity(
  p_race_kind public.race_entry_race_kind,
  p_race_catalog_id uuid,
  p_race_label text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_label text;
begin
  v_label := nullif(btrim(p_race_label), '');

  if p_race_kind is null then
    raise exception 'race-entry race kind is required'
      using errcode = '23514';
  end if;

  if p_race_kind = 'CATALOG'::public.race_entry_race_kind then
    if p_race_catalog_id is null or v_label is not null then
      raise exception 'a catalog race requires an active catalog race and no free-text label'
        using errcode = '23514';
    end if;

    perform 1
    from public.race_catalog
    where id = p_race_catalog_id
      and is_active
    for key share;

    if not found then
      raise exception 'selected race catalog entry does not exist or is inactive'
        using errcode = '23514';
    end if;
  elsif p_race_catalog_id is not null or v_label is null then
    raise exception 'a non-catalog race requires a free-text race label and no catalog race'
      using errcode = '23514';
  end if;
end;
$$;

-- The GM confirmation paths share one lock-and-validate routine so a direct
-- GM schedule cannot drift from the eligibility rules applied to a PLAYER
-- request. It returns the locked Horse, including the authoritative Owner.
create function public.validate_confirmed_race_entry(
  p_horse_id uuid,
  p_expected_owner_id uuid,
  p_wp_year integer,
  p_wp_month smallint,
  p_wp_week smallint,
  p_race_kind public.race_entry_race_kind,
  p_race_catalog_id uuid,
  p_race_label text
)
returns public.horses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
begin
  select *
  into v_horse
  from public.horses
  where id = p_horse_id
  for update;

  if not found or v_horse.owner_id is null then
    raise exception 'a confirmed race schedule requires an existing Horse with an Owner'
      using errcode = '23514';
  end if;

  if p_expected_owner_id is not null and v_horse.owner_id <> p_expected_owner_id then
    raise exception 'race-entry request Horse ownership no longer matches the requesting Owner'
      using errcode = '23514';
  end if;

  if v_horse.life_stage <> 'ACTIVE'::public.horse_life_stage then
    raise exception 'only ACTIVE Horses may receive confirmed race schedules'
      using errcode = '23514';
  end if;

  perform public.assert_race_entry_wp_time_not_past(p_wp_year, p_wp_month, p_wp_week);
  perform public.assert_race_entry_identity(p_race_kind, p_race_catalog_id, p_race_label);

  if exists (
    select 1
    from public.injuries as injury
    where injury.horse_id = v_horse.id
      and injury.status = 'ACTIVE'::public.injury_status
      and (injury.wp_start_year, injury.wp_start_month, injury.wp_start_week)
        <= (p_wp_year, p_wp_month, p_wp_week)
      and (injury.wp_end_year, injury.wp_end_month, injury.wp_end_week)
        >= (p_wp_year, p_wp_month, p_wp_week)
  ) then
    raise exception 'an ACTIVE injury covers the confirmed race-entry WP week'
      using errcode = '23514';
  end if;

  return v_horse;
end;
$$;

create function public.submit_race_entry_request(
  p_horse_id uuid,
  p_requested_wp_year integer,
  p_requested_wp_month smallint,
  p_requested_wp_week smallint,
  p_requested_race_kind public.race_entry_race_kind,
  p_requested_race_catalog_id uuid,
  p_requested_race_label text default null,
  p_requested_jockey text default null,
  p_requested_running_style text default null,
  p_player_note text default null
)
returns public.race_entry_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_horse_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
  v_request public.race_entry_requests%rowtype;
begin
  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null
  for key share;

  if auth.uid() is null or not found then
    raise exception 'only a PLAYER with an Owner may submit a race-entry request'
      using errcode = '42501';
  end if;

  select horse.owner_id, horse.life_stage
  into v_horse_owner_id, v_horse_life_stage
  from public.horses as horse
  where horse.id = p_horse_id
  for update;

  if not found or v_horse_owner_id <> v_owner_id then
    raise exception 'a PLAYER may request races only for Horses owned by that PLAYER'
      using errcode = '42501';
  end if;

  if v_horse_life_stage <> 'ACTIVE'::public.horse_life_stage then
    raise exception 'only ACTIVE Horses may receive race-entry requests'
      using errcode = '23514';
  end if;

  perform public.assert_race_entry_wp_time_not_past(
    p_requested_wp_year, p_requested_wp_month, p_requested_wp_week
  );
  perform public.assert_race_entry_identity(
    p_requested_race_kind, p_requested_race_catalog_id, p_requested_race_label
  );

  insert into public.race_entry_requests (
    horse_id, owner_id, requested_by_user_id,
    requested_wp_year, requested_wp_month, requested_wp_week,
    requested_race_kind, requested_race_catalog_id, requested_race_label,
    requested_jockey, requested_running_style, player_note
  ) values (
    p_horse_id, v_owner_id, auth.uid(),
    p_requested_wp_year, p_requested_wp_month, p_requested_wp_week,
    p_requested_race_kind, p_requested_race_catalog_id, nullif(btrim(p_requested_race_label), ''),
    nullif(btrim(p_requested_jockey), ''), nullif(btrim(p_requested_running_style), ''),
    nullif(btrim(p_player_note), '')
  ) returning * into v_request;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'PLAYER'::public.app_role, 'RACE_ENTRY_REQUEST_CREATED',
    'race_entry_requests', v_request.id::text,
    jsonb_build_object(
      'horse_id', v_request.horse_id,
      'owner_id', v_request.owner_id,
      'requested_wp_year', v_request.requested_wp_year,
      'requested_wp_month', v_request.requested_wp_month,
      'requested_wp_week', v_request.requested_wp_week,
      'requested_race_kind', v_request.requested_race_kind,
      'requested_race_catalog_id', v_request.requested_race_catalog_id,
      'requested_race_label', v_request.requested_race_label
    )
  );

  return v_request;
end;
$$;

create function public.withdraw_race_entry_request(p_request_id uuid)
returns public.race_entry_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_request public.race_entry_requests%rowtype;
  v_before_data jsonb;
begin
  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null
  for key share;

  if auth.uid() is null or not found then
    raise exception 'only a PLAYER with an Owner may withdraw a race-entry request'
      using errcode = '42501';
  end if;

  select *
  into v_request
  from public.race_entry_requests
  where id = p_request_id
  for update;

  if not found or v_request.owner_id <> v_owner_id then
    raise exception 'a PLAYER may withdraw only that PLAYER Owner''s race-entry request'
      using errcode = '42501';
  end if;

  if v_request.status <> 'PENDING'::public.race_entry_request_status then
    raise exception 'only PENDING race-entry requests may be withdrawn'
      using errcode = '23514';
  end if;

  v_before_data := jsonb_build_object('status', v_request.status);

  update public.race_entry_requests
  set status = 'WITHDRAWN'::public.race_entry_request_status,
      withdrawn_by_user_id = auth.uid(),
      withdrawn_at = clock_timestamp()
  where id = v_request.id
  returning * into v_request;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'PLAYER'::public.app_role, 'RACE_ENTRY_REQUEST_WITHDRAWN',
    'race_entry_requests', v_request.id::text, v_before_data,
    jsonb_build_object('status', v_request.status)
  );

  return v_request;
end;
$$;

create function public.confirm_race_entry_request(
  p_request_id uuid,
  p_confirmed_wp_year integer,
  p_confirmed_wp_month smallint,
  p_confirmed_wp_week smallint,
  p_confirmed_race_kind public.race_entry_race_kind,
  p_confirmed_race_catalog_id uuid,
  p_confirmed_race_label text,
  p_confirmed_jockey text,
  p_confirmed_running_style text,
  p_gm_note text
)
returns public.confirmed_race_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.race_entry_requests%rowtype;
  v_entry public.confirmed_race_entries%rowtype;
  v_horse public.horses%rowtype;
  v_normalized_label text;
  v_normalized_jockey text;
  v_normalized_running_style text;
  v_normalized_gm_note text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may confirm a race-entry request'
      using errcode = '42501';
  end if;

  v_normalized_label := nullif(btrim(p_confirmed_race_label), '');
  v_normalized_jockey := nullif(btrim(p_confirmed_jockey), '');
  v_normalized_running_style := nullif(btrim(p_confirmed_running_style), '');
  v_normalized_gm_note := nullif(btrim(p_gm_note), '');

  select *
  into v_request
  from public.race_entry_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'race-entry request does not exist'
      using errcode = 'P0001';
  end if;

  if v_request.status = 'CONFIRMED'::public.race_entry_request_status then
    select *
    into v_entry
    from public.confirmed_race_entries
    where request_id = v_request.id;

    if not found then
      raise exception 'confirmed race-entry request is missing its confirmed schedule'
        using errcode = '23514';
    end if;

    if v_entry.wp_year is distinct from p_confirmed_wp_year
      or v_entry.wp_month is distinct from p_confirmed_wp_month
      or v_entry.wp_week is distinct from p_confirmed_wp_week
      or v_entry.race_kind is distinct from p_confirmed_race_kind
      or v_entry.race_catalog_id is distinct from p_confirmed_race_catalog_id
      or v_entry.race_label is distinct from v_normalized_label
      or v_entry.jockey is distinct from v_normalized_jockey
      or v_entry.running_style is distinct from v_normalized_running_style
      or v_entry.gm_note is distinct from v_normalized_gm_note then
      raise exception 'a confirmed race-entry request may only be retried with identical final facts'
        using errcode = '23514';
    end if;

    return v_entry;
  end if;

  if v_request.status <> 'PENDING'::public.race_entry_request_status then
    raise exception 'only PENDING race-entry requests may be confirmed'
      using errcode = '23514';
  end if;

  v_horse := public.validate_confirmed_race_entry(
    v_request.horse_id,
    v_request.owner_id,
    p_confirmed_wp_year,
    p_confirmed_wp_month,
    p_confirmed_wp_week,
    p_confirmed_race_kind,
    p_confirmed_race_catalog_id,
    v_normalized_label
  );

  insert into public.confirmed_race_entries (
    request_id, horse_id, owner_id,
    wp_year, wp_month, wp_week,
    race_kind, race_catalog_id, race_label,
    jockey, running_style, gm_note, confirmed_by_user_id
  ) values (
    v_request.id, v_request.horse_id, v_request.owner_id,
    p_confirmed_wp_year, p_confirmed_wp_month, p_confirmed_wp_week,
    p_confirmed_race_kind, p_confirmed_race_catalog_id, v_normalized_label,
    v_normalized_jockey, v_normalized_running_style, v_normalized_gm_note, auth.uid()
  ) returning * into v_entry;

  update public.race_entry_requests
  set status = 'CONFIRMED'::public.race_entry_request_status,
      reviewed_by_user_id = auth.uid(),
      reviewed_at = clock_timestamp()
  where id = v_request.id;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_ENTRY_CONFIRMED',
    'race_entry_requests', v_request.id::text,
    jsonb_build_object(
      'status', v_request.status,
      'requested_wp_year', v_request.requested_wp_year,
      'requested_wp_month', v_request.requested_wp_month,
      'requested_wp_week', v_request.requested_wp_week,
      'requested_race_kind', v_request.requested_race_kind,
      'requested_race_catalog_id', v_request.requested_race_catalog_id,
      'requested_race_label', v_request.requested_race_label
    ),
    jsonb_build_object(
      'status', 'CONFIRMED',
      'confirmed_race_entry_id', v_entry.id,
      'confirmed_wp_year', v_entry.wp_year,
      'confirmed_wp_month', v_entry.wp_month,
      'confirmed_wp_week', v_entry.wp_week,
      'confirmed_race_kind', v_entry.race_kind,
      'confirmed_race_catalog_id', v_entry.race_catalog_id,
      'confirmed_race_label', v_entry.race_label,
      'jockey', v_entry.jockey,
      'running_style', v_entry.running_style
    )
  );

  return v_entry;
end;
$$;

-- GM-authoritative direct schedule for an eligible Horse that has no PLAYER
-- request. The Owner is always derived from the locked Horse; callers cannot
-- supply or substitute an Owner.
create function public.create_gm_confirmed_race_entry(
  p_horse_id uuid,
  p_confirmed_wp_year integer,
  p_confirmed_wp_month smallint,
  p_confirmed_wp_week smallint,
  p_confirmed_race_kind public.race_entry_race_kind,
  p_confirmed_race_catalog_id uuid,
  p_confirmed_race_label text default null,
  p_confirmed_jockey text default null,
  p_confirmed_running_style text default null,
  p_gm_note text default null
)
returns public.confirmed_race_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_entry public.confirmed_race_entries%rowtype;
  v_normalized_label text;
  v_normalized_jockey text;
  v_normalized_running_style text;
  v_normalized_gm_note text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a direct confirmed race schedule'
      using errcode = '42501';
  end if;

  v_normalized_label := nullif(btrim(p_confirmed_race_label), '');
  v_normalized_jockey := nullif(btrim(p_confirmed_jockey), '');
  v_normalized_running_style := nullif(btrim(p_confirmed_running_style), '');
  v_normalized_gm_note := nullif(btrim(p_gm_note), '');

  -- Horse remains the shared serialisation point with request confirmation.
  -- Check a direct retry only after acquiring that lock, so it can safely
  -- return the original entry even if game time, Horse state, injuries, or
  -- catalog activation changed after the original successful insert.
  select *
  into v_horse
  from public.horses
  where id = p_horse_id
  for update;

  if not found then
    raise exception 'a confirmed race schedule requires an existing Horse with an Owner'
      using errcode = '23514';
  end if;

  select *
  into v_entry
  from public.confirmed_race_entries
  where horse_id = v_horse.id
    and wp_year = p_confirmed_wp_year
    and wp_month = p_confirmed_wp_month
    and wp_week = p_confirmed_wp_week;

  if found then
    if v_entry.request_id is null
      and v_entry.race_kind is not distinct from p_confirmed_race_kind
      and v_entry.race_catalog_id is not distinct from p_confirmed_race_catalog_id
      and v_entry.race_label is not distinct from v_normalized_label
      and v_entry.jockey is not distinct from v_normalized_jockey
      and v_entry.running_style is not distinct from v_normalized_running_style
      and v_entry.gm_note is not distinct from v_normalized_gm_note then
      return v_entry;
    end if;

    raise exception 'Horse already has a different confirmed race schedule in that WP week'
      using errcode = '23505';
  end if;

  -- No existing schedule occupies this Horse/week, so this is a new direct
  -- entry and must satisfy every current final-schedule eligibility rule.
  -- The helper re-locks our own Horse row, which is harmless and preserves
  -- its shared validation implementation with request confirmation.
  v_horse := public.validate_confirmed_race_entry(
    p_horse_id,
    null,
    p_confirmed_wp_year,
    p_confirmed_wp_month,
    p_confirmed_wp_week,
    p_confirmed_race_kind,
    p_confirmed_race_catalog_id,
    v_normalized_label
  );

  -- The insert trigger requires this transaction-local marker in addition to
  -- the GM JWT and matching confirmed_by_user_id checks.
  perform set_config('horserpg.gm_direct_race_entry', 'on', true);

  insert into public.confirmed_race_entries (
    request_id, horse_id, owner_id,
    wp_year, wp_month, wp_week,
    race_kind, race_catalog_id, race_label,
    jockey, running_style, gm_note, confirmed_by_user_id
  ) values (
    null, v_horse.id, v_horse.owner_id,
    p_confirmed_wp_year, p_confirmed_wp_month, p_confirmed_wp_week,
    p_confirmed_race_kind, p_confirmed_race_catalog_id, v_normalized_label,
    v_normalized_jockey, v_normalized_running_style, v_normalized_gm_note, auth.uid()
  ) returning * into v_entry;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_ENTRY_DIRECTLY_CONFIRMED',
    'confirmed_race_entries', v_entry.id::text,
    jsonb_build_object(
      'horse_id', v_entry.horse_id,
      'owner_id', v_entry.owner_id,
      'request_id', null,
      'confirmed_wp_year', v_entry.wp_year,
      'confirmed_wp_month', v_entry.wp_month,
      'confirmed_wp_week', v_entry.wp_week,
      'confirmed_race_kind', v_entry.race_kind,
      'confirmed_race_catalog_id', v_entry.race_catalog_id,
      'confirmed_race_label', v_entry.race_label,
      'jockey', v_entry.jockey,
      'running_style', v_entry.running_style
    )
  );

  return v_entry;
end;
$$;

create function public.reject_race_entry_request(
  p_request_id uuid,
  p_rejection_reason text default null
)
returns public.race_entry_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.race_entry_requests%rowtype;
  v_reason text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may reject a race-entry request'
      using errcode = '42501';
  end if;

  select *
  into v_request
  from public.race_entry_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'race-entry request does not exist'
      using errcode = 'P0001';
  end if;

  if v_request.status <> 'PENDING'::public.race_entry_request_status then
    raise exception 'only PENDING race-entry requests may be rejected'
      using errcode = '23514';
  end if;

  v_reason := nullif(btrim(p_rejection_reason), '');

  update public.race_entry_requests
  set status = 'REJECTED'::public.race_entry_request_status,
      reviewed_by_user_id = auth.uid(),
      reviewed_at = clock_timestamp(),
      rejection_reason = v_reason
  where id = v_request.id
  returning * into v_request;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'RACE_ENTRY_REJECTED',
    'race_entry_requests', v_request.id::text,
    jsonb_build_object('status', 'PENDING'),
    jsonb_build_object('status', v_request.status),
    v_reason
  );

  return v_request;
end;
$$;

alter table public.race_catalog enable row level security;
alter table public.race_entry_requests enable row level security;
alter table public.confirmed_race_entries enable row level security;

-- Catalog races are authenticated game information. Raw requests remain
-- private intent (requester Owner plus GM). The base confirmed-entry table is
-- GM-only; authenticated Players receive the deliberately narrow public view.
create policy race_catalog_select_authenticated
on public.race_catalog
for select to authenticated
using (true);

create policy race_catalog_write_gm
on public.race_catalog
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy race_entry_requests_select_owner_or_gm
on public.race_entry_requests
for select to authenticated
using (
  owner_id = public.current_player_owner_id()
  or public.is_current_user_gm()
);

create policy confirmed_race_entries_select_gm
on public.confirmed_race_entries
for select to authenticated
using (public.is_current_user_gm());

-- The public schedule intentionally excludes request provenance, GM notes,
-- and the confirming GM. This remains a security-definer view so it can read
-- the GM-only base table; security_invoker would break legitimate PLAYER
-- schedule reads.
create view public.confirmed_race_entries_public
with (security_barrier = true)
as
select
  id,
  horse_id,
  owner_id,
  wp_year,
  wp_month,
  wp_week,
  race_kind,
  race_catalog_id,
  race_label,
  jockey,
  running_style,
  confirmed_at
from public.confirmed_race_entries;

revoke all on table public.race_catalog from public, anon, authenticated, service_role;
revoke all on table public.race_entry_requests from public, anon, authenticated, service_role;
revoke all on table public.confirmed_race_entries from public, anon, authenticated, service_role;
revoke all on table public.confirmed_race_entries_public from public, anon, authenticated, service_role;

grant select, insert, update, delete on table public.race_catalog to authenticated;
grant select on table public.race_entry_requests to authenticated;
grant select on table public.confirmed_race_entries to authenticated;
grant select on table public.confirmed_race_entries_public to authenticated;

-- Client-facing writes are only through the four functions below. All
-- helpers stay non-callable despite SECURITY DEFINER being required inside
-- the trusted execution path.
revoke all on function public.enforce_confirmed_race_entry_request_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_race_entry_request_resolution_integrity() from public, anon, authenticated, service_role;
revoke all on function public.assert_race_entry_wp_time_not_past(integer, smallint, smallint) from public, anon, authenticated, service_role;
revoke all on function public.assert_race_entry_identity(public.race_entry_race_kind, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.validate_confirmed_race_entry(uuid, uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.submit_race_entry_request(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.withdraw_race_entry_request(uuid) from public, anon, authenticated, service_role;
revoke all on function public.confirm_race_entry_request(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.create_gm_confirmed_race_entry(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) from public, anon, authenticated, service_role;
revoke all on function public.reject_race_entry_request(uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.submit_race_entry_request(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) to authenticated;
grant execute on function public.withdraw_race_entry_request(uuid) to authenticated;
grant execute on function public.confirm_race_entry_request(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) to authenticated;
grant execute on function public.create_gm_confirmed_race_entry(uuid, integer, smallint, smallint, public.race_entry_race_kind, uuid, text, text, text, text) to authenticated;
grant execute on function public.reject_race_entry_request(uuid, text) to authenticated;

comment on table public.race_catalog is
  'GM-maintained selectable fixed races. default_wp_month/week are reference defaults, not final-schedule constraints.';
comment on table public.race_entry_requests is
  'Private PLAYER participation intent. Requested facts remain immutable through GM confirmation or rejection.';
comment on table public.confirmed_race_entries is
  'GM-authoritative future schedule. It may originate from one Player request or a controlled GM direct entry; one Horse may have at most one confirmed entry in one final WP week.';
comment on view public.confirmed_race_entries_public is
  'Authenticated public projection of confirmed race schedules; excludes request provenance and GM-private confirmation data.';

commit;
