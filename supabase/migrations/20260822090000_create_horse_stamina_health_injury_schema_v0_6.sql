-- HorseRPG v0.6-A: GM-confirmed stamina, post-race health facts, and
-- controlled injury lifecycle. This migration records only GM decisions; it
-- does not calculate fatigue, recovery, injury probability, or eligibility
-- from stamina.

-- PostgreSQL cannot use a new enum value until the transaction that adds it
-- commits. Keep this retry-safe enum extension outside the main transaction.
-- Supabase wraps a migration file in a transaction, so first close that outer
-- transaction exactly as the v0.4-E enum migration does.
begin;
commit;

alter type public.injury_status add value if not exists 'VOIDED';

begin;

create type public.horse_health_event_type as enum (
  'POST_RACE',
  'MANUAL_ADJUSTMENT'
);

create type public.horse_health_event_status as enum (
  'ACTIVE',
  'VOIDED'
);

-- NULL is a deliberate first-class state: the Horse is not managed by the
-- optional stamina system. Zero is a managed, exhausted Horse, never NULL.
alter table public.horses
  add column current_stamina smallint,
  add constraint horses_current_stamina_range_check
    check (current_stamina is null or current_stamina between 0 and 100);

create table public.horse_health_events (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  event_type public.horse_health_event_type not null,
  race_result_id uuid references public.race_results(id) on delete restrict,
  replaces_health_event_id uuid references public.horse_health_events(id) on delete restrict,
  event_sequence bigint not null check (event_sequence > 0),
  wp_year integer not null check (wp_year > 0),
  wp_month smallint not null check (wp_month between 1 and 12),
  wp_week smallint not null check (wp_week between 1 and 5),
  stamina_before smallint,
  stamina_after smallint,
  notes text,
  status public.horse_health_event_status not null default 'ACTIVE'::public.horse_health_event_status,
  request_id uuid not null unique,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default clock_timestamp(),
  voided_by_user_id uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint horse_health_events_stamina_before_range_check
    check (stamina_before is null or stamina_before between 0 and 100),
  constraint horse_health_events_stamina_after_range_check
    check (stamina_after is null or stamina_after between 0 and 100),
  constraint horse_health_events_result_identity_check check (
    (event_type = 'POST_RACE'::public.horse_health_event_type and race_result_id is not null)
    or
    (event_type = 'MANUAL_ADJUSTMENT'::public.horse_health_event_type and race_result_id is null)
  ),
  constraint horse_health_events_replacement_identity_check check (
    replaces_health_event_id is null or replaces_health_event_id <> id
  ),
  constraint horse_health_events_void_state_check check (
    (
      status = 'ACTIVE'::public.horse_health_event_status
      and voided_by_user_id is null
      and voided_at is null
      and void_reason is null
    )
    or
    (
      status = 'VOIDED'::public.horse_health_event_status
      and voided_at is not null
      and void_reason is not null
      and length(btrim(void_reason)) > 0
    )
  )
);

create unique index horse_health_events_horse_sequence_idx
  on public.horse_health_events (horse_id, event_sequence);

create unique index horse_health_events_one_active_post_race_per_result_idx
  on public.horse_health_events (race_result_id)
  where event_type = 'POST_RACE'::public.horse_health_event_type
    and status = 'ACTIVE'::public.horse_health_event_status;

create unique index horse_health_events_one_replacement_per_event_idx
  on public.horse_health_events (replaces_health_event_id)
  where replaces_health_event_id is not null;

create index horse_health_events_horse_active_sequence_idx
  on public.horse_health_events (horse_id, event_sequence desc)
  where status = 'ACTIVE'::public.horse_health_event_status;

create index horse_health_events_race_result_idx
  on public.horse_health_events (race_result_id)
  where race_result_id is not null;

-- Keep the legacy public injuries row shape unchanged. Existing PLAYER pages
-- select only its legacy columns, while v0.6 lifecycle/source facts remain in
-- this separate GM-only table and therefore cannot be obtained through the
-- Core injuries SELECT policy.
create table public.injury_private_metadata (
  injury_id uuid primary key references public.injuries(id) on delete restrict,
  source_health_event_id uuid references public.horse_health_events(id) on delete restrict,
  resolved_by_user_id uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  resolution_reason text,
  voided_by_user_id uuid references auth.users(id) on delete set null,
  voided_at timestamptz,
  void_reason text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint injury_private_metadata_resolution_state_check check (
    (resolved_at is null and resolution_reason is null)
    or
    (resolved_at is not null and resolution_reason is not null and length(btrim(resolution_reason)) > 0)
  ),
  constraint injury_private_metadata_void_state_check check (
    (voided_at is null and void_reason is null)
    or
    (voided_at is not null and void_reason is not null and length(btrim(void_reason)) > 0)
  )
);

create index injury_private_metadata_source_health_event_id_idx
  on public.injury_private_metadata (source_health_event_id)
  where source_health_event_id is not null;

comment on table public.condition_records is
  'Legacy generic GM condition-outcome records. v0.6 stamina uses horse_health_events as its sole current-stamina fact chain.';

comment on column public.horses.current_stamina is
  'Optional GM-confirmed current stamina: NULL means unmanaged, while 0 through 100 are managed values. It is changed only by controlled health-event RPCs.';

comment on table public.horse_health_events is
  'Append-only GM-confirmed stamina and post-race health fact chain. ACTIVE events are historical facts; only the latest ACTIVE event may be corrected or voided.';

-- Protect optional stamina from legacy Horse CRUD. The local setting is opened
-- only around the one UPDATE performed by the trusted health-event routines.
create function public.prevent_direct_horse_stamina_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' and new.current_stamina is not null then
    raise exception 'horses.current_stamina must be NULL on ordinary Horse creation; use adjust_horse_stamina after creation'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
    and new.current_stamina is distinct from old.current_stamina
    and current_setting('horserpg.stamina_transition', true) is distinct from 'on' then
    raise exception 'horses.current_stamina is controlled by horse health events; use the stamina RPCs'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger horses_prevent_direct_stamina_mutation
before insert or update of current_stamina on public.horses
for each row execute function public.prevent_direct_horse_stamina_mutation();

create function public.prevent_horse_health_event_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and current_setting('horserpg.health_event_transition', true) = 'on' then
    return new;
  end if;

  -- Auth account deletion performs a nested ON DELETE SET NULL update. It may
  -- only erase an optional historical actor, never alter a health fact. Do not
  -- compare updated_at here: the ordinary set_updated_at trigger is allowed to
  -- maintain it for this FK-driven update.
  if tg_op = 'UPDATE'
    and pg_trigger_depth() > 1
    and (
      (old.confirmed_by_user_id is not null and new.confirmed_by_user_id is null)
      or (old.voided_by_user_id is not null and new.voided_by_user_id is null)
    )
    and (
      new.confirmed_by_user_id is not distinct from old.confirmed_by_user_id
      or (old.confirmed_by_user_id is not null and new.confirmed_by_user_id is null)
    )
    and (
      new.voided_by_user_id is not distinct from old.voided_by_user_id
      or (old.voided_by_user_id is not null and new.voided_by_user_id is null)
    )
    and new.id is not distinct from old.id
    and new.horse_id is not distinct from old.horse_id
    and new.event_type is not distinct from old.event_type
    and new.race_result_id is not distinct from old.race_result_id
    and new.replaces_health_event_id is not distinct from old.replaces_health_event_id
    and new.event_sequence is not distinct from old.event_sequence
    and new.wp_year is not distinct from old.wp_year
    and new.wp_month is not distinct from old.wp_month
    and new.wp_week is not distinct from old.wp_week
    and new.stamina_before is not distinct from old.stamina_before
    and new.stamina_after is not distinct from old.stamina_after
    and new.notes is not distinct from old.notes
    and new.status is not distinct from old.status
    and new.request_id is not distinct from old.request_id
    and new.confirmed_at is not distinct from old.confirmed_at
    and new.voided_at is not distinct from old.voided_at
    and new.void_reason is not distinct from old.void_reason
    and new.created_at is not distinct from old.created_at then
    return new;
  end if;

  raise exception 'horse_health_events are append-only; use controlled correction or void flows'
    using errcode = '55000';
end;
$$;

create trigger horse_health_events_prevent_mutation
before update or delete on public.horse_health_events
for each row execute function public.prevent_horse_health_event_mutation();

create trigger horse_health_events_set_updated_at
before update on public.horse_health_events
for each row execute function public.set_updated_at();

create trigger injury_private_metadata_set_updated_at
before update on public.injury_private_metadata
for each row execute function public.set_updated_at();

create function public.enforce_injury_private_metadata_source()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_injury public.injuries%rowtype;
  v_event public.horse_health_events%rowtype;
begin
  if tg_op = 'UPDATE'
    and new.source_health_event_id is distinct from old.source_health_event_id
    and current_setting('horserpg.injury_source_transition', true) is distinct from 'on' then
    raise exception 'injury source health event is controlled by post-race health flows'
      using errcode = '23514';
  end if;

  if new.source_health_event_id is not null
    and current_setting('horserpg.injury_source_transition', true) is distinct from 'on' then
    raise exception 'injury source health event is controlled by post-race health flows'
      using errcode = '23514';
  end if;

  select * into v_injury
  from public.injuries
  where id = new.injury_id
  for key share;

  if not found then
    raise exception 'injury private metadata requires an existing injury'
      using errcode = '23503';
  end if;

  if new.source_health_event_id is null then
    return new;
  end if;

  select * into v_event
  from public.horse_health_events
  where id = new.source_health_event_id
  for key share;

  if not found
    or v_event.event_type <> 'POST_RACE'::public.horse_health_event_type
    or v_event.horse_id <> v_injury.horse_id then
    raise exception 'an injury source health event must be a same-Horse POST_RACE event'
      using errcode = '23514';
  end if;

  if v_injury.status <> 'VOIDED'::public.injury_status
    and v_event.status <> 'ACTIVE'::public.horse_health_event_status then
    raise exception 'a non-VOIDED injury must reference an ACTIVE source health event'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger injury_private_metadata_enforce_source
before insert or update of injury_id, source_health_event_id on public.injury_private_metadata
for each row execute function public.enforce_injury_private_metadata_source();

create function public.enforce_injury_source_health_event_invariant()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_event_horse_id uuid;
  v_event_type public.horse_health_event_type;
  v_event_status public.horse_health_event_status;
begin
  select event.horse_id, event.event_type, event.status
  into v_event_horse_id, v_event_type, v_event_status
  from public.injury_private_metadata as metadata
  join public.horse_health_events as event on event.id = metadata.source_health_event_id
  where metadata.injury_id = new.id;

  if not found then
    return new;
  end if;

  if v_event_type <> 'POST_RACE'::public.horse_health_event_type
    or v_event_horse_id <> new.horse_id then
    raise exception 'an injury source health event must be a same-Horse POST_RACE event'
      using errcode = '23514';
  end if;

  if new.status <> 'VOIDED'::public.injury_status
    and v_event_status <> 'ACTIVE'::public.horse_health_event_status then
    raise exception 'a non-VOIDED injury cannot reference a non-ACTIVE health event'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and current_setting('horserpg.injury_lifecycle_transition', true) is distinct from 'on' then
    raise exception 'source-linked injury lifecycle is controlled by health and injury RPCs'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger injuries_enforce_source_health_event_invariant
before update of horse_id, status on public.injuries
for each row execute function public.enforce_injury_source_health_event_invariant();

create function public.prevent_voided_health_event_with_effective_injury()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'VOIDED'::public.horse_health_event_status
    and old.status <> new.status
    and exists (
      select 1
      from public.injury_private_metadata as metadata
      join public.injuries as injury on injury.id = metadata.injury_id
      where metadata.source_health_event_id = new.id
        and injury.status <> 'VOIDED'::public.injury_status
    ) then
    raise exception 'source injuries must be voided before their health event is voided'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger horse_health_events_prevent_void_with_source_injuries
before update of status on public.horse_health_events
for each row execute function public.prevent_voided_health_event_with_effective_injury();

create function public.horse_health_event_audit_data(
  p_event public.horse_health_events
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_event.id,
    'horse_id', p_event.horse_id,
    'event_type', p_event.event_type,
    'race_result_id', p_event.race_result_id,
    'replaces_health_event_id', p_event.replaces_health_event_id,
    'event_sequence', p_event.event_sequence,
    'wp_year', p_event.wp_year,
    'wp_month', p_event.wp_month,
    'wp_week', p_event.wp_week,
    'stamina_before', p_event.stamina_before,
    'stamina_after', p_event.stamina_after,
    'status', p_event.status
  );
$$;

create function public.injury_audit_data(
  p_injury public.injuries
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_injury.id,
    'horse_id', p_injury.horse_id,
    'source_health_event_id', (
      select metadata.source_health_event_id
      from public.injury_private_metadata as metadata
      where metadata.injury_id = p_injury.id
    ),
    'status', p_injury.status,
    'wp_start_year', p_injury.wp_start_year,
    'wp_start_month', p_injury.wp_start_month,
    'wp_start_week', p_injury.wp_start_week,
    'wp_end_year', p_injury.wp_end_year,
    'wp_end_month', p_injury.wp_end_month,
    'wp_end_week', p_injury.wp_end_week,
    'resolved_at', (
      select metadata.resolved_at
      from public.injury_private_metadata as metadata
      where metadata.injury_id = p_injury.id
    ),
    'resolution_reason', (
      select metadata.resolution_reason
      from public.injury_private_metadata as metadata
      where metadata.injury_id = p_injury.id
    ),
    'voided_at', (
      select metadata.voided_at
      from public.injury_private_metadata as metadata
      where metadata.injury_id = p_injury.id
    ),
    'void_reason', (
      select metadata.void_reason
      from public.injury_private_metadata as metadata
      where metadata.injury_id = p_injury.id
    )
  );
$$;

create function public.assert_stamina_value(p_stamina smallint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_stamina is not null and p_stamina not between 0 and 100 then
    raise exception 'stamina must be an integer between 0 and 100'
      using errcode = '23514';
  end if;
end;
$$;

create function public.assert_health_event_wp_time_appendable(
  p_horse_id uuid,
  p_wp_year integer,
  p_wp_month smallint,
  p_wp_week smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_wp_year is null or p_wp_year <= 0
    or p_wp_month is null or p_wp_month not between 1 and 12
    or p_wp_week is null or p_wp_week not between 1 and 5 then
    raise exception 'horse health event WP time is invalid'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.horse_health_events
    where horse_id = p_horse_id
      and status = 'ACTIVE'::public.horse_health_event_status
      and (wp_year, wp_month, wp_week) > (p_wp_year, p_wp_month, p_wp_week)
  ) then
    raise exception 'cannot append a horse health event before a later active health event'
      using errcode = '23514';
  end if;
end;
$$;

create function public.assert_horse_current_stamina_chain(
  p_horse public.horses
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_latest public.horse_health_events%rowtype;
begin
  select *
  into v_latest
  from public.horse_health_events
  where horse_id = p_horse.id
    and status = 'ACTIVE'::public.horse_health_event_status
  order by event_sequence desc
  limit 1
  for update;

  if found and v_latest.stamina_after is distinct from p_horse.current_stamina then
    raise exception 'Horse current_stamina does not match its latest active health event'
      using errcode = '23514';
  end if;
end;
$$;

create function public.next_horse_health_event_sequence(p_horse_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(max(event_sequence), 0) + 1
  from public.horse_health_events
  where horse_id = p_horse_id;
$$;

create function public.apply_horse_stamina_transition(
  p_horse_id uuid,
  p_stamina_after smallint
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('horserpg.stamina_transition', 'on', true);
  update public.horses
  set current_stamina = p_stamina_after
  where id = p_horse_id;
  perform set_config('horserpg.stamina_transition', 'off', true);
end;
$$;

create function public.void_source_injuries_for_health_event(
  p_health_event_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_injury public.injuries%rowtype;
  v_before jsonb;
begin
  for v_injury in
    select injury.*
    from public.injuries as injury
    join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
    where metadata.source_health_event_id = p_health_event_id
      and injury.status <> 'VOIDED'::public.injury_status
    order by injury.id
    for update
  loop
    v_before := public.injury_audit_data(v_injury);

    update public.injury_private_metadata
    set voided_by_user_id = auth.uid(),
        voided_at = clock_timestamp(),
        void_reason = p_reason
    where injury_id = v_injury.id;

    perform set_config('horserpg.injury_lifecycle_transition', 'on', true);
    update public.injuries
    set status = 'VOIDED'::public.injury_status
    where id = v_injury.id
    returning * into v_injury;
    perform set_config('horserpg.injury_lifecycle_transition', 'off', true);

    insert into public.audit_logs (
      actor_user_id, actor_role, action, entity_type, entity_id,
      before_data, after_data, reason
    ) values (
      auth.uid(), 'GM'::public.app_role, 'INJURY_VOIDED', 'injuries',
      v_injury.id::text, v_before, public.injury_audit_data(v_injury), p_reason
    );
  end loop;
end;
$$;

-- Caller must already hold the source Horse lock. This keeps result void,
-- manual void, and correction on the same Horse-level serialisation point.
create function public.void_latest_horse_health_event_locked(
  p_health_event_id uuid,
  p_reason text,
  p_audit_action text default 'HORSE_HEALTH_EVENT_VOIDED'
)
returns public.horse_health_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.horse_health_events%rowtype;
  v_latest public.horse_health_events%rowtype;
  v_before jsonb;
begin
  select *
  into v_event
  from public.horse_health_events
  where id = p_health_event_id
  for update;

  if not found then
    raise exception 'horse health event does not exist'
      using errcode = '23503';
  end if;

  if v_event.status = 'VOIDED'::public.horse_health_event_status then
    if v_event.void_reason is distinct from p_reason then
      raise exception 'a voided horse health event cannot have its void reason changed'
        using errcode = '23514';
    end if;
    return v_event;
  end if;

  select *
  into v_latest
  from public.horse_health_events
  where horse_id = v_event.horse_id
    and status = 'ACTIVE'::public.horse_health_event_status
  order by event_sequence desc
  limit 1
  for update;

  if not found or v_latest.id <> v_event.id then
    raise exception 'only the latest active horse health event may be voided; reverse later health events first'
      using errcode = '23514';
  end if;

  v_before := public.horse_health_event_audit_data(v_event);
  perform public.void_source_injuries_for_health_event(v_event.id, p_reason);

  perform set_config('horserpg.health_event_transition', 'on', true);
  update public.horse_health_events
  set status = 'VOIDED'::public.horse_health_event_status,
      voided_by_user_id = auth.uid(),
      voided_at = clock_timestamp(),
      void_reason = p_reason
  where id = v_event.id
  returning * into v_event;
  perform set_config('horserpg.health_event_transition', 'off', true);

  perform public.apply_horse_stamina_transition(v_event.horse_id, v_event.stamina_before);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, p_audit_action, 'horse_health_events',
    v_event.id::text, v_before, public.horse_health_event_audit_data(v_event), p_reason
  );

  return v_event;
end;
$$;

create function public.record_post_race_health(
  p_request_id uuid,
  p_race_result_id uuid,
  p_stamina_after smallint default null,
  p_injury_start_year integer default null,
  p_injury_start_month smallint default null,
  p_injury_start_week smallint default null,
  p_injury_end_year integer default null,
  p_injury_end_month smallint default null,
  p_injury_end_week smallint default null,
  p_injury_notes text default null,
  p_notes text default null
)
returns public.horse_health_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.race_results%rowtype;
  v_actual_race public.actual_races%rowtype;
  v_horse public.horses%rowtype;
  v_existing public.horse_health_events%rowtype;
  v_event public.horse_health_events%rowtype;
  v_existing_injury public.injuries%rowtype;
  v_injury public.injuries%rowtype;
  v_notes text := nullif(btrim(p_notes), '');
  v_injury_notes text := nullif(btrim(p_injury_notes), '');
  v_has_injury boolean;
  v_expected_sequence bigint;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may record post-race health'
      using errcode = '42501';
  end if;

  if p_request_id is null then
    raise exception 'post-race health request_id is required'
      using errcode = '23514';
  end if;

  v_has_injury := p_injury_start_year is not null
    or p_injury_start_month is not null
    or p_injury_start_week is not null
    or p_injury_end_year is not null
    or p_injury_end_month is not null
    or p_injury_end_week is not null
    or v_injury_notes is not null;

  if v_has_injury and (
    p_injury_start_year is null or p_injury_start_month is null or p_injury_start_week is null
    or p_injury_end_year is null or p_injury_end_month is null or p_injury_end_week is null
  ) then
    raise exception 'post-race injury requires complete WP start and end facts'
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

  select *
  into v_actual_race
  from public.actual_races
  where id = v_result.actual_race_id
  for key share;

  if not found then
    raise exception 'race result actual race does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_horse
  from public.horses
  where id = v_result.horse_id
  for update;

  if not found then
    raise exception 'race result Horse does not exist'
      using errcode = '23503';
  end if;

  select *
  into v_existing
  from public.horse_health_events
  where race_result_id = v_result.id
    and event_type = 'POST_RACE'::public.horse_health_event_type
    and status = 'ACTIVE'::public.horse_health_event_status
  for update;

  if found then
    select injury.*
    into v_existing_injury
    from public.injuries as injury
    join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
    where metadata.source_health_event_id = v_existing.id
      and injury.status <> 'VOIDED'::public.injury_status
    order by injury.id
    limit 1
    for update;

    if v_existing.request_id = p_request_id
      and v_existing.stamina_after is not distinct from p_stamina_after
      and v_existing.notes is not distinct from v_notes
      and (
        (not v_has_injury and not found)
        or (
          v_has_injury and found
          and v_existing_injury.wp_start_year = p_injury_start_year
          and v_existing_injury.wp_start_month = p_injury_start_month
          and v_existing_injury.wp_start_week = p_injury_start_week
          and v_existing_injury.wp_end_year = p_injury_end_year
          and v_existing_injury.wp_end_month = p_injury_end_month
          and v_existing_injury.wp_end_week = p_injury_end_week
          and v_existing_injury.notes is not distinct from v_injury_notes
          and not exists (
            select 1
            from public.injuries as extra
            join public.injury_private_metadata as extra_metadata on extra_metadata.injury_id = extra.id
            where extra_metadata.source_health_event_id = v_existing.id
              and extra.status <> 'VOIDED'::public.injury_status
              and extra.id <> v_existing_injury.id
          )
        )
      ) then
      return v_existing;
    end if;

    if v_existing.request_id = p_request_id then
      raise exception 'post-race health request_id already exists with different facts'
        using errcode = '23505';
    end if;

    raise exception 'race result already has an active post-race health event'
      using errcode = '23505';
  end if;

  if v_result.status <> 'CONFIRMED'::public.race_result_status then
    raise exception 'only a confirmed race result may receive post-race health'
      using errcode = '23514';
  end if;

  perform public.assert_stamina_value(p_stamina_after);
  perform public.assert_health_event_wp_time_appendable(
    v_horse.id, v_actual_race.wp_year, v_actual_race.wp_month, v_actual_race.wp_week
  );
  perform public.assert_horse_current_stamina_chain(v_horse);

  if v_horse.current_stamina is null and p_stamina_after is not null then
    raise exception 'POST_RACE cannot enable stamina management; use adjust_horse_stamina'
      using errcode = '23514';
  end if;

  if v_horse.current_stamina is not null and p_stamina_after is null then
    raise exception 'POST_RACE cannot disable stamina management; use adjust_horse_stamina'
      using errcode = '23514';
  end if;

  v_expected_sequence := public.next_horse_health_event_sequence(v_horse.id);
  insert into public.horse_health_events (
    horse_id, event_type, race_result_id, event_sequence,
    wp_year, wp_month, wp_week,
    stamina_before, stamina_after, notes, request_id,
    confirmed_by_user_id
  ) values (
    v_horse.id, 'POST_RACE'::public.horse_health_event_type, v_result.id, v_expected_sequence,
    v_actual_race.wp_year, v_actual_race.wp_month, v_actual_race.wp_week,
    v_horse.current_stamina, p_stamina_after, v_notes, p_request_id,
    auth.uid()
  ) returning * into v_event;

  perform public.apply_horse_stamina_transition(v_horse.id, p_stamina_after);

  if v_has_injury then
    insert into public.injuries (
      horse_id, status,
      wp_start_year, wp_start_month, wp_start_week,
      wp_end_year, wp_end_month, wp_end_week,
      notes, confirmed_by_user_id
    ) values (
      v_horse.id, 'ACTIVE'::public.injury_status,
      p_injury_start_year, p_injury_start_month, p_injury_start_week,
      p_injury_end_year, p_injury_end_month, p_injury_end_week,
      v_injury_notes, auth.uid()
    ) returning * into v_injury;

    perform set_config('horserpg.injury_source_transition', 'on', true);
    insert into public.injury_private_metadata (injury_id, source_health_event_id)
    values (v_injury.id, v_event.id);
    perform set_config('horserpg.injury_source_transition', 'off', true);

    insert into public.audit_logs (
      actor_user_id, actor_role, action, entity_type, entity_id, after_data
    ) values (
      auth.uid(), 'GM'::public.app_role, 'INJURY_CREATED', 'injuries',
      v_injury.id::text, public.injury_audit_data(v_injury)
    );
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, request_id
  ) values (
    auth.uid(), 'GM'::public.app_role, 'HORSE_POST_RACE_HEALTH_RECORDED',
    'horse_health_events', v_event.id::text, public.horse_health_event_audit_data(v_event), p_request_id
  );

  return v_event;
end;
$$;

create function public.adjust_horse_stamina(
  p_horse_id uuid,
  p_stamina_after smallint,
  p_reason text,
  p_request_id uuid
)
returns public.horse_health_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_existing public.horse_health_events%rowtype;
  v_event public.horse_health_events%rowtype;
  v_game_state public.game_state%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_sequence bigint;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may adjust Horse stamina'
      using errcode = '42501';
  end if;

  if p_request_id is null then
    raise exception 'stamina-adjustment request_id is required'
      using errcode = '23514';
  end if;

  if v_reason is null then
    raise exception 'manual stamina adjustment reason is required'
      using errcode = '23514';
  end if;

  perform public.assert_stamina_value(p_stamina_after);

  select * into v_horse
  from public.horses
  where id = p_horse_id
  for update;

  if not found then
    raise exception 'Horse does not exist'
      using errcode = '23503';
  end if;

  select * into v_existing
  from public.horse_health_events
  where request_id = p_request_id
  for update;

  if found then
    if v_existing.horse_id = v_horse.id
      and v_existing.event_type = 'MANUAL_ADJUSTMENT'::public.horse_health_event_type
      and v_existing.status = 'ACTIVE'::public.horse_health_event_status
      and v_existing.stamina_after is not distinct from p_stamina_after
      and v_existing.notes = v_reason then
      return v_existing;
    end if;

    raise exception 'stamina-adjustment request_id already exists with different facts'
      using errcode = '23505';
  end if;

  perform public.assert_horse_current_stamina_chain(v_horse);

  if v_horse.current_stamina is not distinct from p_stamina_after then
    raise exception 'manual stamina adjustment must change the current stamina state'
      using errcode = '23514';
  end if;

  select * into v_game_state
  from public.game_state
  for share;

  if not found then
    raise exception 'game state must be initialized before manual stamina adjustment'
      using errcode = '23514';
  end if;

  perform public.assert_health_event_wp_time_appendable(
    v_horse.id, v_game_state.current_wp_year, v_game_state.current_wp_month, v_game_state.current_wp_week
  );

  v_sequence := public.next_horse_health_event_sequence(v_horse.id);
  insert into public.horse_health_events (
    horse_id, event_type, event_sequence, wp_year, wp_month, wp_week,
    stamina_before, stamina_after, notes, request_id, confirmed_by_user_id
  ) values (
    v_horse.id, 'MANUAL_ADJUSTMENT'::public.horse_health_event_type,
    v_sequence, v_game_state.current_wp_year, v_game_state.current_wp_month, v_game_state.current_wp_week,
    v_horse.current_stamina, p_stamina_after, v_reason, p_request_id, auth.uid()
  ) returning * into v_event;

  perform public.apply_horse_stamina_transition(v_horse.id, p_stamina_after);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason, request_id
  ) values (
    auth.uid(), 'GM'::public.app_role, 'HORSE_STAMINA_ADJUSTED', 'horse_health_events',
    v_event.id::text, public.horse_health_event_audit_data(v_event), v_reason, p_request_id
  );

  return v_event;
end;
$$;

create function public.create_manual_injury(
  p_horse_id uuid,
  p_wp_start_year integer,
  p_wp_start_month smallint,
  p_wp_start_week smallint,
  p_wp_end_year integer,
  p_wp_end_month smallint,
  p_wp_end_week smallint,
  p_notes text default null
)
returns public.injuries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_injury public.injuries%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create an injury'
      using errcode = '42501';
  end if;

  select * into v_horse
  from public.horses
  where id = p_horse_id
  for update;

  if not found then
    raise exception 'Horse does not exist'
      using errcode = '23503';
  end if;

  insert into public.injuries (
    horse_id, status,
    wp_start_year, wp_start_month, wp_start_week,
    wp_end_year, wp_end_month, wp_end_week,
    notes, confirmed_by_user_id
  ) values (
    v_horse.id, 'ACTIVE'::public.injury_status,
    p_wp_start_year, p_wp_start_month, p_wp_start_week,
    p_wp_end_year, p_wp_end_month, p_wp_end_week,
    nullif(btrim(p_notes), ''), auth.uid()
  ) returning * into v_injury;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'INJURY_CREATED', 'injuries',
    v_injury.id::text, public.injury_audit_data(v_injury)
  );

  return v_injury;
end;
$$;

create function public.resolve_injury(
  p_injury_id uuid,
  p_reason text
)
returns public.injuries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse_id uuid;
  v_injury public.injuries%rowtype;
  v_metadata public.injury_private_metadata%rowtype;
  v_before jsonb;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may resolve an injury'
      using errcode = '42501';
  end if;
  if v_reason is null then
    raise exception 'injury resolution reason is required'
      using errcode = '23514';
  end if;

  select horse_id into v_horse_id from public.injuries where id = p_injury_id;
  if not found then
    raise exception 'injury does not exist' using errcode = '23503';
  end if;
  perform 1 from public.horses where id = v_horse_id for update;
  select * into v_injury from public.injuries where id = p_injury_id for update;
  insert into public.injury_private_metadata (injury_id)
  values (v_injury.id)
  on conflict (injury_id) do nothing;
  select * into v_metadata from public.injury_private_metadata where injury_id = v_injury.id for update;

  if v_injury.status = 'RECOVERED'::public.injury_status then
    if v_metadata.resolution_reason is not distinct from v_reason then return v_injury; end if;
    raise exception 'a recovered injury cannot have its resolution reason changed' using errcode = '23514';
  end if;
  if v_injury.status <> 'ACTIVE'::public.injury_status then
    raise exception 'only an ACTIVE injury may be resolved' using errcode = '23514';
  end if;

  v_before := public.injury_audit_data(v_injury);
  update public.injury_private_metadata
  set resolved_by_user_id = auth.uid(), resolved_at = clock_timestamp(), resolution_reason = v_reason
  where injury_id = v_injury.id;
  perform set_config('horserpg.injury_lifecycle_transition', 'on', true);
  update public.injuries
  set status = 'RECOVERED'::public.injury_status
  where id = v_injury.id returning * into v_injury;
  perform set_config('horserpg.injury_lifecycle_transition', 'off', true);

  insert into public.audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason)
  values (auth.uid(), 'GM'::public.app_role, 'INJURY_RESOLVED', 'injuries', v_injury.id::text, v_before, public.injury_audit_data(v_injury), v_reason);
  return v_injury;
end;
$$;

create function public.void_injury(
  p_injury_id uuid,
  p_reason text
)
returns public.injuries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse_id uuid;
  v_injury public.injuries%rowtype;
  v_metadata public.injury_private_metadata%rowtype;
  v_before jsonb;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then raise exception 'only a GM may void an injury' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'injury void reason is required' using errcode = '23514'; end if;
  select horse_id into v_horse_id from public.injuries where id = p_injury_id;
  if not found then raise exception 'injury does not exist' using errcode = '23503'; end if;
  perform 1 from public.horses where id = v_horse_id for update;
  select * into v_injury from public.injuries where id = p_injury_id for update;
  insert into public.injury_private_metadata (injury_id)
  values (v_injury.id)
  on conflict (injury_id) do nothing;
  select * into v_metadata from public.injury_private_metadata where injury_id = v_injury.id for update;

  if v_injury.status = 'VOIDED'::public.injury_status then
    if v_metadata.void_reason is not distinct from v_reason then return v_injury; end if;
    raise exception 'a voided injury cannot have its void reason changed' using errcode = '23514';
  end if;

  v_before := public.injury_audit_data(v_injury);
  update public.injury_private_metadata
  set voided_by_user_id = auth.uid(), voided_at = clock_timestamp(), void_reason = v_reason
  where injury_id = v_injury.id;
  perform set_config('horserpg.injury_lifecycle_transition', 'on', true);
  update public.injuries
  set status = 'VOIDED'::public.injury_status
  where id = v_injury.id returning * into v_injury;
  perform set_config('horserpg.injury_lifecycle_transition', 'off', true);
  insert into public.audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason)
  values (auth.uid(), 'GM'::public.app_role, 'INJURY_VOIDED', 'injuries', v_injury.id::text, v_before, public.injury_audit_data(v_injury), v_reason);
  return v_injury;
end;
$$;

create function public.correct_latest_horse_health_event(
  p_health_event_id uuid,
  p_stamina_after smallint,
  p_notes text,
  p_reason text,
  p_request_id uuid,
  p_injury_start_year integer default null,
  p_injury_start_month smallint default null,
  p_injury_start_week smallint default null,
  p_injury_end_year integer default null,
  p_injury_end_month smallint default null,
  p_injury_end_week smallint default null,
  p_injury_notes text default null
)
returns public.horse_health_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_identity public.horse_health_events%rowtype;
  v_target public.horse_health_events%rowtype;
  v_latest public.horse_health_events%rowtype;
  v_horse public.horses%rowtype;
  v_result public.race_results%rowtype;
  v_existing public.horse_health_events%rowtype;
  v_replacement public.horse_health_events%rowtype;
  v_existing_injury public.injuries%rowtype;
  v_injury public.injuries%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_notes text := nullif(btrim(p_notes), '');
  v_injury_notes text := nullif(btrim(p_injury_notes), '');
  v_has_injury boolean;
  v_effective_injury_count bigint;
  v_before jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then raise exception 'only a GM may correct a horse health event' using errcode = '42501'; end if;
  if p_request_id is null then raise exception 'horse health correction request_id is required' using errcode = '23514'; end if;
  if v_reason is null then raise exception 'horse health correction reason is required' using errcode = '23514'; end if;

  v_has_injury := p_injury_start_year is not null or p_injury_start_month is not null or p_injury_start_week is not null
    or p_injury_end_year is not null or p_injury_end_month is not null or p_injury_end_week is not null or v_injury_notes is not null;

  -- Read the immutable identity first. A POST_RACE correction then takes the
  -- same Result -> Horse -> Health Event route as void_race_result, so the two
  -- operations cannot form a Horse/Result lock cycle.
  select * into v_identity from public.horse_health_events where id = p_health_event_id;
  if not found then raise exception 'horse health event does not exist' using errcode = '23503'; end if;

  if v_identity.event_type = 'POST_RACE'::public.horse_health_event_type then
    select * into v_result
    from public.race_results
    where id = v_identity.race_result_id
    for update;
    if not found
      or v_result.status <> 'CONFIRMED'::public.race_result_status
      or v_result.horse_id <> v_identity.horse_id then
      raise exception 'POST_RACE correction requires its confirmed matching race result'
        using errcode = '23514';
    end if;
  end if;

  select * into v_horse from public.horses where id = v_identity.horse_id for update;
  select * into v_target from public.horse_health_events where id = p_health_event_id for update;

  if v_target.horse_id <> v_identity.horse_id
    or v_target.event_type <> v_identity.event_type
    or v_target.race_result_id is distinct from v_identity.race_result_id then
    raise exception 'horse health event identity changed while acquiring correction locks'
      using errcode = '40001';
  end if;

  if v_target.event_type = 'MANUAL_ADJUSTMENT'::public.horse_health_event_type and v_has_injury then
    raise exception 'MANUAL_ADJUSTMENT corrections cannot create source injuries'
      using errcode = '23514';
  end if;

  select * into v_existing from public.horse_health_events where request_id = p_request_id;
  if found then
    if v_existing.replaces_health_event_id is distinct from v_target.id
      or v_existing.horse_id is distinct from v_target.horse_id
      or v_existing.event_type is distinct from v_target.event_type
      or v_existing.race_result_id is distinct from v_target.race_result_id then
      raise exception 'horse health correction request_id already exists with different facts' using errcode = '23505';
    end if;

    select count(*) into v_effective_injury_count
    from public.injuries as injury
    join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
    where metadata.source_health_event_id = v_existing.id
      and injury.status <> 'VOIDED'::public.injury_status;

    select injury.* into v_existing_injury
    from public.injuries as injury
    join public.injury_private_metadata as metadata on metadata.injury_id = injury.id
    where metadata.source_health_event_id = v_existing.id
      and injury.status <> 'VOIDED'::public.injury_status
    order by injury.id
    limit 1
    for update;

    if v_existing.stamina_before is not distinct from v_target.stamina_before
      and v_existing.stamina_after is not distinct from p_stamina_after
      and v_existing.notes is not distinct from v_notes
      and v_target.status = 'VOIDED'::public.horse_health_event_status
      and v_target.void_reason is not distinct from v_reason
      and (
        (not v_has_injury and v_effective_injury_count = 0)
        or (
          v_has_injury and v_effective_injury_count = 1
          and v_existing_injury.wp_start_year = p_injury_start_year
          and v_existing_injury.wp_start_month = p_injury_start_month
          and v_existing_injury.wp_start_week = p_injury_start_week
          and v_existing_injury.wp_end_year = p_injury_end_year
          and v_existing_injury.wp_end_month = p_injury_end_month
          and v_existing_injury.wp_end_week = p_injury_end_week
          and v_existing_injury.notes is not distinct from v_injury_notes
        )
      ) then
      return v_existing;
    end if;

    raise exception 'horse health correction request_id already exists with different facts' using errcode = '23505';
  end if;

  perform public.assert_stamina_value(p_stamina_after);
  if v_has_injury and (p_injury_start_year is null or p_injury_start_month is null or p_injury_start_week is null or p_injury_end_year is null or p_injury_end_month is null or p_injury_end_week is null) then
    raise exception 'replacement injury requires complete WP start and end facts' using errcode = '23514';
  end if;

  if v_target.status <> 'ACTIVE'::public.horse_health_event_status then raise exception 'only an active horse health event may be corrected' using errcode = '23514'; end if;
  select * into v_latest from public.horse_health_events where horse_id = v_target.horse_id and status = 'ACTIVE'::public.horse_health_event_status order by event_sequence desc limit 1 for update;
  if not found or v_latest.id <> v_target.id then raise exception 'only the latest active horse health event may be corrected; reverse later health events first' using errcode = '23514'; end if;
  perform public.assert_horse_current_stamina_chain(v_horse);

  if v_target.event_type = 'POST_RACE'::public.horse_health_event_type and ((v_target.stamina_before is null and p_stamina_after is not null) or (v_target.stamina_before is not null and p_stamina_after is null)) then
    raise exception 'POST_RACE correction cannot enable or disable stamina management' using errcode = '23514';
  end if;
  if v_target.event_type = 'MANUAL_ADJUSTMENT'::public.horse_health_event_type and v_target.stamina_before is not distinct from p_stamina_after then
    raise exception 'manual stamina correction must change the prior stamina state' using errcode = '23514';
  end if;

  v_before := public.horse_health_event_audit_data(v_target);
  perform public.void_source_injuries_for_health_event(v_target.id, 'Health event correction: ' || v_reason);
  perform set_config('horserpg.health_event_transition', 'on', true);
  update public.horse_health_events set status = 'VOIDED'::public.horse_health_event_status, voided_by_user_id = auth.uid(), voided_at = clock_timestamp(), void_reason = v_reason where id = v_target.id returning * into v_target;
  perform set_config('horserpg.health_event_transition', 'off', true);

  insert into public.horse_health_events (
    horse_id, event_type, race_result_id, replaces_health_event_id, event_sequence,
    wp_year, wp_month, wp_week, stamina_before, stamina_after, notes, request_id, confirmed_by_user_id
  ) values (
    v_target.horse_id, v_target.event_type, v_target.race_result_id, v_target.id,
    public.next_horse_health_event_sequence(v_target.horse_id),
    v_target.wp_year, v_target.wp_month, v_target.wp_week,
    v_target.stamina_before, p_stamina_after, v_notes, p_request_id, auth.uid()
  ) returning * into v_replacement;

  perform public.apply_horse_stamina_transition(v_target.horse_id, p_stamina_after);

  if v_has_injury then
    insert into public.injuries (horse_id, status, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week, notes, confirmed_by_user_id)
    values (v_target.horse_id, 'ACTIVE'::public.injury_status, p_injury_start_year, p_injury_start_month, p_injury_start_week, p_injury_end_year, p_injury_end_month, p_injury_end_week, v_injury_notes, auth.uid()) returning * into v_injury;
    perform set_config('horserpg.injury_source_transition', 'on', true);
    insert into public.injury_private_metadata (injury_id, source_health_event_id)
    values (v_injury.id, v_replacement.id);
    perform set_config('horserpg.injury_source_transition', 'off', true);
    insert into public.audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, after_data)
    values (auth.uid(), 'GM'::public.app_role, 'INJURY_CREATED', 'injuries', v_injury.id::text, public.injury_audit_data(v_injury));
  end if;

  insert into public.audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason, request_id)
  values (auth.uid(), 'GM'::public.app_role, 'HORSE_HEALTH_EVENT_CORRECTED', 'horse_health_events', v_target.id::text, v_before, public.horse_health_event_audit_data(v_replacement), v_reason, p_request_id);
  return v_replacement;
end;
$$;

create function public.void_latest_horse_health_event(
  p_health_event_id uuid,
  p_reason text
)
returns public.horse_health_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse_id uuid;
  v_event public.horse_health_events%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then raise exception 'only a GM may void a horse health event' using errcode = '42501'; end if;
  if v_reason is null then raise exception 'horse health event void reason is required' using errcode = '23514'; end if;
  select horse_id into v_horse_id from public.horse_health_events where id = p_health_event_id;
  if not found then raise exception 'horse health event does not exist' using errcode = '23503'; end if;
  perform 1 from public.horses where id = v_horse_id for update;
  select * into v_event from public.horse_health_events where id = p_health_event_id for update;
  if v_event.status = 'VOIDED'::public.horse_health_event_status then
    if v_event.void_reason is not distinct from v_reason then return v_event; end if;
    raise exception 'a voided horse health event cannot have its void reason changed' using errcode = '23514';
  end if;
  return public.void_latest_horse_health_event_locked(v_event.id, v_reason, 'HORSE_HEALTH_EVENT_VOIDED');
end;
$$;

-- Replace only the existing v0.4-C void path. Race-result correction remains
-- deliberately independent from GM-confirmed health facts.
create or replace function public.void_race_result(
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
  v_horse public.horses%rowtype;
  v_health_event public.horse_health_events%rowtype;
  v_reason text;
  v_before_data jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then raise exception 'only a GM may void a race result' using errcode = '42501'; end if;
  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then raise exception 'race-result void reason is required' using errcode = '23514'; end if;

  select * into v_result from public.race_results where id = p_race_result_id for update;
  if not found then raise exception 'race result does not exist' using errcode = '23503'; end if;
  if v_result.status = 'VOIDED'::public.race_result_status then
    if v_result.void_reason is distinct from v_reason then raise exception 'a voided race result cannot have its void reason changed' using errcode = '23514'; end if;
    return v_result;
  end if;

  select * into v_horse from public.horses where id = v_result.horse_id for update;
  if not found then raise exception 'race result Horse does not exist' using errcode = '23503'; end if;
  select * into v_health_event from public.horse_health_events
  where race_result_id = v_result.id and event_type = 'POST_RACE'::public.horse_health_event_type and status = 'ACTIVE'::public.horse_health_event_status
  for update;
  if found then
    perform public.void_latest_horse_health_event_locked(v_health_event.id, 'Race result void: ' || v_reason, 'HORSE_HEALTH_EVENT_VOIDED');
  end if;

  v_before_data := public.race_result_audit_data(v_result);
  update public.race_results set status = 'VOIDED'::public.race_result_status, voided_by_user_id = auth.uid(), voided_at = clock_timestamp(), void_reason = v_reason where id = v_result.id returning * into v_result;
  insert into public.audit_logs (actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason)
  values (auth.uid(), 'GM'::public.app_role, 'RACE_RESULT_VOIDED', 'race_results', v_result.id::text, v_before_data, public.race_result_audit_data(v_result), v_reason);
  return v_result;
end;
$$;

alter table public.horse_health_events enable row level security;
alter table public.injury_private_metadata enable row level security;

create policy horse_health_events_select_gm
on public.horse_health_events
for select to authenticated
using (public.is_current_user_gm());

create policy injury_private_metadata_select_gm
on public.injury_private_metadata
for select to authenticated
using (public.is_current_user_gm());

-- Player-facing health history excludes request IDs, actor IDs, audit reasons,
-- and GM notes. It deliberately exposes NULL stamina as NULL, not zero.
create view public.horse_health_events_public
with (security_barrier = true)
as
select id, horse_id, event_type, wp_year, wp_month, wp_week, stamina_before, stamina_after, status
from public.horse_health_events;

-- Existing application pages read public.injuries directly for race scheduling.
-- Keep that deployed compatibility for v0.6-A, while providing the safe view
-- that v0.6-B can switch to before base-table reads are narrowed.
create view public.injuries_public
with (security_barrier = true)
as
select
  id, horse_id, status,
  wp_start_year, wp_start_month, wp_start_week,
  wp_end_year, wp_end_month, wp_end_week,
  notes
from public.injuries;

-- Preserve the Core GM-only direct legacy-injury administration path. The
-- existing RLS write policy rejects every PLAYER; Core never granted DELETE.
grant insert, update on table public.injuries to authenticated;

revoke all on table public.horse_health_events from public, anon, authenticated, service_role;
revoke all on table public.injury_private_metadata from public, anon, authenticated, service_role;
revoke all on table public.horse_health_events_public from public, anon, authenticated, service_role;
revoke all on table public.injuries_public from public, anon, authenticated, service_role;

grant select on table public.horse_health_events to authenticated;
grant select on table public.injury_private_metadata to authenticated;
grant select on table public.horse_health_events_public to authenticated;
grant select on table public.injuries_public to authenticated;

-- All public-facing mutation functions verify GM identity internally. Helpers,
-- guard triggers, and audit serializers remain non-callable from every client role.
revoke all on function public.horse_health_event_audit_data(public.horse_health_events) from public, anon, authenticated, service_role;
revoke all on function public.injury_audit_data(public.injuries) from public, anon, authenticated, service_role;
revoke all on function public.assert_stamina_value(smallint) from public, anon, authenticated, service_role;
revoke all on function public.assert_health_event_wp_time_appendable(uuid, integer, smallint, smallint) from public, anon, authenticated, service_role;
revoke all on function public.assert_horse_current_stamina_chain(public.horses) from public, anon, authenticated, service_role;
revoke all on function public.next_horse_health_event_sequence(uuid) from public, anon, authenticated, service_role;
revoke all on function public.apply_horse_stamina_transition(uuid, smallint) from public, anon, authenticated, service_role;
revoke all on function public.void_source_injuries_for_health_event(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.void_latest_horse_health_event_locked(uuid, text, text) from public, anon, authenticated, service_role;
revoke all on function public.prevent_direct_horse_stamina_mutation() from public, anon, authenticated, service_role;
revoke all on function public.prevent_horse_health_event_mutation() from public, anon, authenticated, service_role;
revoke all on function public.enforce_injury_private_metadata_source() from public, anon, authenticated, service_role;
revoke all on function public.enforce_injury_source_health_event_invariant() from public, anon, authenticated, service_role;
revoke all on function public.prevent_voided_health_event_with_effective_injury() from public, anon, authenticated, service_role;

revoke all on function public.record_post_race_health(uuid, uuid, smallint, integer, smallint, smallint, integer, smallint, smallint, text, text) from public, anon, authenticated, service_role;
revoke all on function public.adjust_horse_stamina(uuid, smallint, text, uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_manual_injury(uuid, integer, smallint, smallint, integer, smallint, smallint, text) from public, anon, authenticated, service_role;
revoke all on function public.resolve_injury(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.void_injury(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.correct_latest_horse_health_event(uuid, smallint, text, text, uuid, integer, smallint, smallint, integer, smallint, smallint, text) from public, anon, authenticated, service_role;
revoke all on function public.void_latest_horse_health_event(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.void_race_result(uuid, text) from public, anon, authenticated, service_role;

grant execute on function public.record_post_race_health(uuid, uuid, smallint, integer, smallint, smallint, integer, smallint, smallint, text, text) to authenticated;
grant execute on function public.adjust_horse_stamina(uuid, smallint, text, uuid) to authenticated;
grant execute on function public.create_manual_injury(uuid, integer, smallint, smallint, integer, smallint, smallint, text) to authenticated;
grant execute on function public.resolve_injury(uuid, text) to authenticated;
grant execute on function public.void_injury(uuid, text) to authenticated;
grant execute on function public.correct_latest_horse_health_event(uuid, smallint, text, text, uuid, integer, smallint, smallint, integer, smallint, smallint, text) to authenticated;
grant execute on function public.void_latest_horse_health_event(uuid, text) to authenticated;
grant execute on function public.void_race_result(uuid, text) to authenticated;

comment on view public.horse_health_events_public is
  'Authenticated-safe health history projection. It excludes notes, request IDs, actor identities, void reasons, and audit data.';

comment on view public.injuries_public is
  'Future authenticated-safe injury projection. Existing v0.4 application routes still use public.injuries and must migrate to this view before base read access can be narrowed.';

commit;
