-- HorseRPG v0.5-A: Breeding candidates, optional pedigree references, and
-- controlled creation of a WP-confirmed foal. This records facts only; it
-- does not model mating, pregnancy, genetics, or any Winning Post simulation.

begin;

create type public.breeding_candidate_type as enum ('STALLION', 'BROODMARE');
create type public.pedigree_parent_source_type as enum ('INTERNAL', 'REFERENCE', 'MANUAL');

create table public.pedigree_reference_horses (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(btrim(name)) > 0),
  translated_name text,
  sex text check (sex is null or sex in ('MALE', 'FEMALE', 'GELDING')),
  sire_line text,
  sire_name text,
  dam_name text,
  broodmare_sire_name text,
  aliases text[] not null default '{}'::text[],
  notes text,
  is_active boolean not null default true,
  created_by_user_id uuid references auth.users(id) on delete set null,
  updated_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint pedigree_reference_horses_translated_name_check check (
    translated_name is null or length(btrim(translated_name)) > 0
  ),
  constraint pedigree_reference_horses_sire_line_check check (
    sire_line is null or length(btrim(sire_line)) > 0
  ),
  constraint pedigree_reference_horses_sire_name_check check (
    sire_name is null or length(btrim(sire_name)) > 0
  ),
  constraint pedigree_reference_horses_dam_name_check check (
    dam_name is null or length(btrim(dam_name)) > 0
  ),
  constraint pedigree_reference_horses_broodmare_sire_name_check check (
    broodmare_sire_name is null or length(btrim(broodmare_sire_name)) > 0
  )
);

create index pedigree_reference_horses_active_name_idx
  on public.pedigree_reference_horses (is_active, name);

create table public.breeding_candidates (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null unique references public.horses(id) on delete restrict,
  candidate_type public.breeding_candidate_type not null,
  is_active boolean not null default true,
  notes text,
  added_by_user_id uuid references auth.users(id) on delete set null,
  added_at timestamptz not null default clock_timestamp(),
  deactivated_by_user_id uuid references auth.users(id) on delete set null,
  deactivated_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint breeding_candidates_deactivation_state_check check (
    (is_active and deactivated_at is null)
    or (not is_active and deactivated_at is not null)
  )
);

create index breeding_candidates_active_type_idx
  on public.breeding_candidates (candidate_type, horse_id)
  where is_active;

-- Historical Horses remain valid without any data backfill. A v0.5 foal has
-- both source fields set, but earlier records may keep all six fields NULL.
alter table public.horses
  add column dam_name text,
  add column sire_parent_source_type public.pedigree_parent_source_type,
  add column dam_parent_source_type public.pedigree_parent_source_type,
  add column sire_horse_id uuid references public.horses(id) on delete restrict,
  add column dam_horse_id uuid references public.horses(id) on delete restrict,
  add column sire_reference_id uuid references public.pedigree_reference_horses(id) on delete restrict,
  add column dam_reference_id uuid references public.pedigree_reference_horses(id) on delete restrict,
  add constraint horses_dam_name_check check (
    dam_name is null or length(btrim(dam_name)) > 0
  ),
  add constraint horses_sire_parent_source_shape_check check (
    (
      sire_parent_source_type is null
      and sire_horse_id is null
      and sire_reference_id is null
    )
    or (
      sire_parent_source_type = 'INTERNAL'::public.pedigree_parent_source_type
      and sire_horse_id is not null
      and sire_reference_id is null
    )
    or (
      sire_parent_source_type = 'REFERENCE'::public.pedigree_parent_source_type
      and sire_horse_id is null
      and sire_reference_id is not null
    )
    or (
      sire_parent_source_type = 'MANUAL'::public.pedigree_parent_source_type
      and sire_horse_id is null
      and sire_reference_id is null
    )
  ),
  add constraint horses_dam_parent_source_shape_check check (
    (
      dam_parent_source_type is null
      and dam_horse_id is null
      and dam_reference_id is null
    )
    or (
      dam_parent_source_type = 'INTERNAL'::public.pedigree_parent_source_type
      and dam_horse_id is not null
      and dam_reference_id is null
    )
    or (
      dam_parent_source_type = 'REFERENCE'::public.pedigree_parent_source_type
      and dam_horse_id is null
      and dam_reference_id is not null
    )
    or (
      dam_parent_source_type = 'MANUAL'::public.pedigree_parent_source_type
      and dam_horse_id is null
      and dam_reference_id is null
    )
  );

create index horses_sire_horse_id_idx on public.horses (sire_horse_id) where sire_horse_id is not null;
create index horses_dam_horse_id_idx on public.horses (dam_horse_id) where dam_horse_id is not null;
create index horses_sire_reference_id_idx on public.horses (sire_reference_id) where sire_reference_id is not null;
create index horses_dam_reference_id_idx on public.horses (dam_reference_id) where dam_reference_id is not null;

-- This is an internal idempotency ledger, not a breeding, pregnancy, or mating
-- model. It prevents one timed-out GM request from creating two foals.
create table public.foal_creation_requests (
  request_id uuid primary key,
  horse_id uuid not null unique references public.horses(id) on delete restrict,
  request_facts jsonb not null check (jsonb_typeof(request_facts) = 'object'),
  created_by_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp()
);

create function public.enforce_breeding_candidate_horse_eligibility()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_expected_type public.breeding_candidate_type;
begin
  select * into v_horse
  from public.horses
  where id = new.horse_id
  for update;

  if not found then
    raise exception 'breeding candidate Horse does not exist'
      using errcode = '23503';
  end if;

  if v_horse.sex = 'MALE' then
    v_expected_type := 'STALLION'::public.breeding_candidate_type;
  elsif v_horse.sex = 'FEMALE' then
    v_expected_type := 'BROODMARE'::public.breeding_candidate_type;
  else
    raise exception 'only MALE or FEMALE Horse may be a breeding candidate'
      using errcode = '23514';
  end if;

  if new.candidate_type <> v_expected_type then
    raise exception 'breeding candidate type does not match Horse sex'
      using errcode = '23514';
  end if;

  if new.is_active and v_horse.life_stage <> 'RETIRED'::public.horse_life_stage then
    raise exception 'only a RETIRED Horse may be an active breeding candidate'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger breeding_candidates_enforce_horse_eligibility
before insert or update of horse_id, candidate_type, is_active on public.breeding_candidates
for each row execute function public.enforce_breeding_candidate_horse_eligibility();

create trigger breeding_candidates_set_updated_at
before update on public.breeding_candidates
for each row execute function public.set_updated_at();

create trigger pedigree_reference_horses_set_updated_at
before update on public.pedigree_reference_horses
for each row execute function public.set_updated_at();

create function public.prevent_foal_creation_request_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'foal creation requests are immutable'
    using errcode = '55000';
end;
$$;

create trigger foal_creation_requests_prevent_mutation
before update or delete on public.foal_creation_requests
for each row execute function public.prevent_foal_creation_request_mutation();

-- Structured parent relationships and their resolved text snapshots are birth
-- facts. Legacy Horse CRUD continues to work, but only create_foal may INSERT
-- a structured pedigree and no ordinary update may rewrite its facts.
create function public.prevent_horse_parent_identity_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_candidate public.breeding_candidates%rowtype;
  v_old_is_structured boolean;
  v_identity_changed boolean;
begin
  if tg_op = 'INSERT' then
    if (
      new.sire_parent_source_type is not null
      or new.dam_parent_source_type is not null
      or new.sire_horse_id is not null
      or new.dam_horse_id is not null
      or new.sire_reference_id is not null
      or new.dam_reference_id is not null
    ) and current_setting('horserpg.foal_creation_insert', true) is distinct from 'on' then
      raise exception 'structured Horse pedigree requires controlled Foal creation'
        using errcode = '42501';
    end if;

    return new;
  end if;

  if new.sex is distinct from old.sex then
    select * into v_candidate
    from public.breeding_candidates
    where horse_id = old.id
      and is_active
    for share;

    if found and (
      (v_candidate.candidate_type = 'STALLION'::public.breeding_candidate_type and new.sex <> 'MALE')
      or (v_candidate.candidate_type = 'BROODMARE'::public.breeding_candidate_type and new.sex <> 'FEMALE')
    ) then
      raise exception 'active breeding candidate type must remain compatible with Horse sex'
        using errcode = '23514';
    end if;
  end if;

  v_old_is_structured := old.sire_parent_source_type is not null
    or old.dam_parent_source_type is not null;
  v_identity_changed := new.sire_parent_source_type is distinct from old.sire_parent_source_type
    or new.dam_parent_source_type is distinct from old.dam_parent_source_type
    or new.sire_horse_id is distinct from old.sire_horse_id
    or new.dam_horse_id is distinct from old.dam_horse_id
    or new.sire_reference_id is distinct from old.sire_reference_id
    or new.dam_reference_id is distinct from old.dam_reference_id;

  if (v_old_is_structured and (
    v_identity_changed
    or new.sire_name is distinct from old.sire_name
    or new.sire_line is distinct from old.sire_line
    or new.dam_name is distinct from old.dam_name
    or new.broodmare_sire_name is distinct from old.broodmare_sire_name
  )) or (not v_old_is_structured and v_identity_changed) then
    raise exception 'Horse structured pedigree facts are immutable; use a controlled correction flow'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger horses_prevent_parent_identity_mutation
before insert or update
on public.horses
for each row execute function public.prevent_horse_parent_identity_mutation();

-- Canonical registered-name rule for an internal parent snapshot: Japanese
-- registered name first, then translated registered name, then the original
-- foal-stage name only when no later name exists.
create function public.horse_canonical_registered_name(
  p_horse public.horses
)
returns text
language sql
stable
set search_path = ''
as $$
  select coalesce(
    nullif(btrim(p_horse.name_katakana), ''),
    nullif(btrim(p_horse.translated_name), ''),
    nullif(btrim(p_horse.foal_name), '')
  );
$$;

create function public.breeding_candidate_audit_data(
  p_candidate public.breeding_candidates
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'horse_id', p_candidate.horse_id,
    'candidate_type', p_candidate.candidate_type,
    'is_active', p_candidate.is_active
  );
$$;

create function public.pedigree_reference_horse_audit_data(
  p_reference public.pedigree_reference_horses
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'name', p_reference.name,
    'translated_name', p_reference.translated_name,
    'sex', p_reference.sex,
    'is_active', p_reference.is_active
  );
$$;

create function public.activate_breeding_candidate(
  p_horse_id uuid,
  p_notes text default null
)
returns public.breeding_candidates
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_candidate public.breeding_candidates%rowtype;
  v_candidate_type public.breeding_candidate_type;
  v_notes text := nullif(btrim(p_notes), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may activate a breeding candidate'
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

  if v_horse.life_stage <> 'RETIRED'::public.horse_life_stage then
    raise exception 'only a RETIRED Horse may become a breeding candidate'
      using errcode = '23514';
  end if;

  if v_horse.sex = 'MALE' then
    v_candidate_type := 'STALLION'::public.breeding_candidate_type;
  elsif v_horse.sex = 'FEMALE' then
    v_candidate_type := 'BROODMARE'::public.breeding_candidate_type;
  else
    raise exception 'only MALE or FEMALE Horse may become a breeding candidate'
      using errcode = '23514';
  end if;

  select * into v_candidate
  from public.breeding_candidates
  where horse_id = v_horse.id
  for update;

  if found and v_candidate.is_active then
    return v_candidate;
  end if;

  if found then
    update public.breeding_candidates
    set candidate_type = v_candidate_type,
        is_active = true,
        notes = v_notes,
        added_by_user_id = auth.uid(),
        added_at = clock_timestamp(),
        deactivated_by_user_id = null,
        deactivated_at = null
    where id = v_candidate.id
    returning * into v_candidate;
  else
    insert into public.breeding_candidates (
      horse_id, candidate_type, is_active, notes, added_by_user_id
    ) values (
      v_horse.id, v_candidate_type, true, v_notes, auth.uid()
    ) returning * into v_candidate;
  end if;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'BREEDING_CANDIDATE_ACTIVATED',
    'breeding_candidates', v_candidate.id::text,
    public.breeding_candidate_audit_data(v_candidate)
  );

  return v_candidate;
end;
$$;

create function public.deactivate_breeding_candidate(
  p_horse_id uuid,
  p_reason text default null
)
returns public.breeding_candidates
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_candidate public.breeding_candidates%rowtype;
  v_before jsonb;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may deactivate a breeding candidate'
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

  select * into v_candidate
  from public.breeding_candidates
  where horse_id = v_horse.id
  for update;

  if not found then
    raise exception 'breeding candidate does not exist'
      using errcode = 'P0001';
  end if;

  if not v_candidate.is_active then
    return v_candidate;
  end if;

  v_before := public.breeding_candidate_audit_data(v_candidate);
  update public.breeding_candidates
  set is_active = false,
      deactivated_by_user_id = auth.uid(),
      deactivated_at = clock_timestamp()
  where id = v_candidate.id
  returning * into v_candidate;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'BREEDING_CANDIDATE_DEACTIVATED',
    'breeding_candidates', v_candidate.id::text,
    v_before, public.breeding_candidate_audit_data(v_candidate), v_reason
  );

  return v_candidate;
end;
$$;

create function public.create_pedigree_reference_horse(
  p_name text,
  p_translated_name text default null,
  p_sex text default null,
  p_sire_line text default null,
  p_sire_name text default null,
  p_dam_name text default null,
  p_broodmare_sire_name text default null,
  p_aliases text[] default '{}'::text[],
  p_notes text default null
)
returns public.pedigree_reference_horses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reference public.pedigree_reference_horses%rowtype;
  v_name text := nullif(btrim(p_name), '');
  v_translated_name text := nullif(btrim(p_translated_name), '');
  v_sex text := nullif(btrim(p_sex), '');
  v_sire_line text := nullif(btrim(p_sire_line), '');
  v_sire_name text := nullif(btrim(p_sire_name), '');
  v_dam_name text := nullif(btrim(p_dam_name), '');
  v_broodmare_sire_name text := nullif(btrim(p_broodmare_sire_name), '');
  v_notes text := nullif(btrim(p_notes), '');
  v_aliases text[];
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a pedigree reference Horse'
      using errcode = '42501';
  end if;

  if v_name is null then
    raise exception 'pedigree reference name is required'
      using errcode = '23514';
  end if;

  if v_sex is not null and v_sex not in ('MALE', 'FEMALE', 'GELDING') then
    raise exception 'pedigree reference sex must be MALE, FEMALE, GELDING, or NULL'
      using errcode = '23514';
  end if;

  select coalesce(array_agg(alias order by alias), '{}'::text[])
  into v_aliases
  from (
    select distinct nullif(btrim(value), '') as alias
    from unnest(coalesce(p_aliases, '{}'::text[])) as value
  ) as normalized
  where alias is not null;

  insert into public.pedigree_reference_horses (
    name, translated_name, sex, sire_line, sire_name, dam_name,
    broodmare_sire_name, aliases, notes, created_by_user_id, updated_by_user_id
  ) values (
    v_name, v_translated_name, v_sex, v_sire_line, v_sire_name, v_dam_name,
    v_broodmare_sire_name, v_aliases, v_notes, auth.uid(), auth.uid()
  ) returning * into v_reference;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'PEDIGREE_REFERENCE_CREATED',
    'pedigree_reference_horses', v_reference.id::text,
    public.pedigree_reference_horse_audit_data(v_reference)
  );

  return v_reference;
end;
$$;

create function public.update_pedigree_reference_horse(
  p_reference_id uuid,
  p_name text,
  p_translated_name text default null,
  p_sex text default null,
  p_sire_line text default null,
  p_sire_name text default null,
  p_dam_name text default null,
  p_broodmare_sire_name text default null,
  p_aliases text[] default '{}'::text[],
  p_notes text default null
)
returns public.pedigree_reference_horses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reference public.pedigree_reference_horses%rowtype;
  v_before jsonb;
  v_name text := nullif(btrim(p_name), '');
  v_translated_name text := nullif(btrim(p_translated_name), '');
  v_sex text := nullif(btrim(p_sex), '');
  v_sire_line text := nullif(btrim(p_sire_line), '');
  v_sire_name text := nullif(btrim(p_sire_name), '');
  v_dam_name text := nullif(btrim(p_dam_name), '');
  v_broodmare_sire_name text := nullif(btrim(p_broodmare_sire_name), '');
  v_notes text := nullif(btrim(p_notes), '');
  v_aliases text[];
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may update a pedigree reference Horse'
      using errcode = '42501';
  end if;

  if v_name is null then
    raise exception 'pedigree reference name is required'
      using errcode = '23514';
  end if;

  if v_sex is not null and v_sex not in ('MALE', 'FEMALE', 'GELDING') then
    raise exception 'pedigree reference sex must be MALE, FEMALE, GELDING, or NULL'
      using errcode = '23514';
  end if;

  select * into v_reference
  from public.pedigree_reference_horses
  where id = p_reference_id
  for update;

  if not found then
    raise exception 'pedigree reference Horse does not exist'
      using errcode = 'P0001';
  end if;

  select coalesce(array_agg(alias order by alias), '{}'::text[])
  into v_aliases
  from (
    select distinct nullif(btrim(value), '') as alias
    from unnest(coalesce(p_aliases, '{}'::text[])) as value
  ) as normalized
  where alias is not null;

  v_before := public.pedigree_reference_horse_audit_data(v_reference);
  update public.pedigree_reference_horses
  set name = v_name,
      translated_name = v_translated_name,
      sex = v_sex,
      sire_line = v_sire_line,
      sire_name = v_sire_name,
      dam_name = v_dam_name,
      broodmare_sire_name = v_broodmare_sire_name,
      aliases = v_aliases,
      notes = v_notes,
      updated_by_user_id = auth.uid()
  where id = v_reference.id
  returning * into v_reference;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'PEDIGREE_REFERENCE_UPDATED',
    'pedigree_reference_horses', v_reference.id::text,
    v_before, public.pedigree_reference_horse_audit_data(v_reference)
  );

  return v_reference;
end;
$$;

create function public.deactivate_pedigree_reference_horse(
  p_reference_id uuid,
  p_reason text default null
)
returns public.pedigree_reference_horses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reference public.pedigree_reference_horses%rowtype;
  v_before jsonb;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may deactivate a pedigree reference Horse'
      using errcode = '42501';
  end if;

  select * into v_reference
  from public.pedigree_reference_horses
  where id = p_reference_id
  for update;

  if not found then
    raise exception 'pedigree reference Horse does not exist'
      using errcode = 'P0001';
  end if;

  if not v_reference.is_active then
    return v_reference;
  end if;

  v_before := public.pedigree_reference_horse_audit_data(v_reference);
  update public.pedigree_reference_horses
  set is_active = false,
      updated_by_user_id = auth.uid()
  where id = v_reference.id
  returning * into v_reference;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'PEDIGREE_REFERENCE_DEACTIVATED',
    'pedigree_reference_horses', v_reference.id::text,
    v_before, public.pedigree_reference_horse_audit_data(v_reference), v_reason
  );

  return v_reference;
end;
$$;

create function public.create_foal(
  p_request_id uuid,
  p_horse_number bigint,
  p_birth_year integer,
  p_foal_name text,
  p_name_katakana text,
  p_translated_name text,
  p_sex text,
  p_coat_color text,
  p_sire_source_type public.pedigree_parent_source_type,
  p_sire_horse_id uuid,
  p_sire_reference_id uuid,
  p_manual_sire_name text,
  p_manual_sire_line text,
  p_dam_source_type public.pedigree_parent_source_type,
  p_dam_horse_id uuid,
  p_dam_reference_id uuid,
  p_manual_dam_name text,
  p_manual_broodmare_sire_name text
)
returns public.horses
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_request public.foal_creation_requests%rowtype;
  v_existing_horse public.horses%rowtype;
  v_horse public.horses%rowtype;
  v_parent_horse public.horses%rowtype;
  v_sire_horse public.horses%rowtype;
  v_dam_horse public.horses%rowtype;
  v_sire_candidate public.breeding_candidates%rowtype;
  v_dam_candidate public.breeding_candidates%rowtype;
  v_sire_reference public.pedigree_reference_horses%rowtype;
  v_dam_reference public.pedigree_reference_horses%rowtype;
  v_sire_name text;
  v_sire_line text;
  v_dam_name text;
  v_broodmare_sire_name text;
  v_foal_name text := nullif(btrim(p_foal_name), '');
  v_name_katakana text := nullif(btrim(p_name_katakana), '');
  v_translated_name text := nullif(btrim(p_translated_name), '');
  v_sex text := nullif(btrim(p_sex), '');
  v_coat_color text := nullif(btrim(p_coat_color), '');
  v_manual_sire_name text := nullif(btrim(p_manual_sire_name), '');
  v_manual_sire_line text := nullif(btrim(p_manual_sire_line), '');
  v_manual_dam_name text := nullif(btrim(p_manual_dam_name), '');
  v_manual_broodmare_sire_name text := nullif(btrim(p_manual_broodmare_sire_name), '');
  v_request_facts jsonb;
  v_parent_ids uuid[];
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a Foal'
      using errcode = '42501';
  end if;

  if p_request_id is null then
    raise exception 'Foal creation request_id is required'
      using errcode = '23514';
  end if;

  if p_sire_source_type is null or p_dam_source_type is null then
    raise exception 'both Foal parent source types are required'
      using errcode = '23514';
  end if;

  if p_sire_source_type = 'INTERNAL'::public.pedigree_parent_source_type
    and (p_sire_horse_id is null or p_sire_reference_id is not null) then
    raise exception 'INTERNAL sire requires only sire_horse_id'
      using errcode = '23514';
  elsif p_sire_source_type = 'REFERENCE'::public.pedigree_parent_source_type
    and (p_sire_reference_id is null or p_sire_horse_id is not null) then
    raise exception 'REFERENCE sire requires only sire_reference_id'
      using errcode = '23514';
  elsif p_sire_source_type = 'MANUAL'::public.pedigree_parent_source_type
    and (p_sire_horse_id is not null or p_sire_reference_id is not null) then
    raise exception 'MANUAL sire may not include a parent identifier'
      using errcode = '23514';
  end if;

  if p_dam_source_type = 'INTERNAL'::public.pedigree_parent_source_type
    and (p_dam_horse_id is null or p_dam_reference_id is not null) then
    raise exception 'INTERNAL dam requires only dam_horse_id'
      using errcode = '23514';
  elsif p_dam_source_type = 'REFERENCE'::public.pedigree_parent_source_type
    and (p_dam_reference_id is null or p_dam_horse_id is not null) then
    raise exception 'REFERENCE dam requires only dam_reference_id'
      using errcode = '23514';
  elsif p_dam_source_type = 'MANUAL'::public.pedigree_parent_source_type
    and (p_dam_horse_id is not null or p_dam_reference_id is not null) then
    raise exception 'MANUAL dam may not include a parent identifier'
      using errcode = '23514';
  end if;

  v_request_facts := jsonb_build_object(
    'horse_number', p_horse_number,
    'birth_year', p_birth_year,
    'foal_name', v_foal_name,
    'name_katakana', v_name_katakana,
    'translated_name', v_translated_name,
    'sex', v_sex,
    'coat_color', v_coat_color,
    'sire_source_type', p_sire_source_type,
    'sire_horse_id', p_sire_horse_id,
    'sire_reference_id', p_sire_reference_id,
    'manual_sire_name', v_manual_sire_name,
    'manual_sire_line', v_manual_sire_line,
    'dam_source_type', p_dam_source_type,
    'dam_horse_id', p_dam_horse_id,
    'dam_reference_id', p_dam_reference_id,
    'manual_dam_name', v_manual_dam_name,
    'manual_broodmare_sire_name', v_manual_broodmare_sire_name
  );

  -- A request-scoped advisory lock serializes only retries of this operation.
  perform pg_advisory_xact_lock(hashtextextended(p_request_id::text, 0));
  select * into v_existing_request
  from public.foal_creation_requests
  where request_id = p_request_id
  for update;

  if found then
    if v_existing_request.request_facts is not distinct from v_request_facts then
      select * into v_existing_horse
      from public.horses
      where id = v_existing_request.horse_id;
      if not found then
        raise exception 'Foal creation request has no retained Horse result'
          using errcode = '23514';
      end if;
      return v_existing_horse;
    end if;

    raise exception 'Foal creation request_id already exists with different facts'
      using errcode = '23505';
  end if;

  if p_horse_number is null or p_horse_number <= 0
    or p_birth_year is null or p_birth_year <= 0
    or v_foal_name is null
    or v_sex not in ('MALE', 'FEMALE', 'GELDING')
    or v_coat_color is null then
    raise exception 'Foal requires a positive Horse number, WP birth year, name, sex, and coat color'
      using errcode = '23514';
  end if;

  v_parent_ids := array_remove(array[
    case when p_sire_source_type = 'INTERNAL'::public.pedigree_parent_source_type then p_sire_horse_id end,
    case when p_dam_source_type = 'INTERNAL'::public.pedigree_parent_source_type then p_dam_horse_id end
  ], null);

  for v_parent_horse in
    select *
    from public.horses
    where id = any(v_parent_ids)
    order by id
    for share
  loop
    if v_parent_horse.id = p_sire_horse_id then
      v_sire_horse := v_parent_horse;
    end if;
    if v_parent_horse.id = p_dam_horse_id then
      v_dam_horse := v_parent_horse;
    end if;
  end loop;

  if p_sire_source_type = 'INTERNAL'::public.pedigree_parent_source_type then
    if v_sire_horse.id is null then
      raise exception 'internal sire Horse does not exist'
        using errcode = '23503';
    end if;
    select * into v_sire_candidate
    from public.breeding_candidates
    where horse_id = v_sire_horse.id
    for share;
    if not found or not v_sire_candidate.is_active
      or v_sire_candidate.candidate_type <> 'STALLION'::public.breeding_candidate_type
      or v_sire_horse.sex <> 'MALE'
      or v_sire_horse.life_stage <> 'RETIRED'::public.horse_life_stage then
      raise exception 'internal sire must be an active RETIRED STALLION candidate'
        using errcode = '23514';
    end if;
    v_sire_name := public.horse_canonical_registered_name(v_sire_horse);
    v_sire_line := v_sire_horse.sire_line;
  elsif p_sire_source_type = 'REFERENCE'::public.pedigree_parent_source_type then
    select * into v_sire_reference
    from public.pedigree_reference_horses
    where id = p_sire_reference_id
    for share;
    if not found or not v_sire_reference.is_active
      or (v_sire_reference.sex is not null and v_sire_reference.sex <> 'MALE') then
      raise exception 'reference sire must be active and compatible with MALE'
        using errcode = '23514';
    end if;
    if v_sire_reference.sire_line is null then
      raise exception 'reference sire must include sire_line for the Horse snapshot'
        using errcode = '23514';
    end if;
    v_sire_name := v_sire_reference.name;
    v_sire_line := v_sire_reference.sire_line;
  else
    if v_manual_sire_name is null or v_manual_sire_line is null then
      raise exception 'manual sire requires sire name and sire line'
        using errcode = '23514';
    end if;
    v_sire_name := v_manual_sire_name;
    v_sire_line := v_manual_sire_line;
  end if;

  if p_dam_source_type = 'INTERNAL'::public.pedigree_parent_source_type then
    if v_dam_horse.id is null then
      raise exception 'internal dam Horse does not exist'
        using errcode = '23503';
    end if;
    select * into v_dam_candidate
    from public.breeding_candidates
    where horse_id = v_dam_horse.id
    for share;
    if not found or not v_dam_candidate.is_active
      or v_dam_candidate.candidate_type <> 'BROODMARE'::public.breeding_candidate_type
      or v_dam_horse.sex <> 'FEMALE'
      or v_dam_horse.life_stage <> 'RETIRED'::public.horse_life_stage then
      raise exception 'internal dam must be an active RETIRED BROODMARE candidate'
        using errcode = '23514';
    end if;
    v_dam_name := public.horse_canonical_registered_name(v_dam_horse);
    v_broodmare_sire_name := v_dam_horse.sire_name;
  elsif p_dam_source_type = 'REFERENCE'::public.pedigree_parent_source_type then
    select * into v_dam_reference
    from public.pedigree_reference_horses
    where id = p_dam_reference_id
    for share;
    if not found or not v_dam_reference.is_active
      or (v_dam_reference.sex is not null and v_dam_reference.sex <> 'FEMALE') then
      raise exception 'reference dam must be active and compatible with FEMALE'
        using errcode = '23514';
    end if;
    if v_dam_reference.sire_name is null then
      raise exception 'reference dam must include sire_name for the Horse broodmare sire snapshot'
        using errcode = '23514';
    end if;
    v_dam_name := v_dam_reference.name;
    v_broodmare_sire_name := v_dam_reference.sire_name;
  else
    -- Current Horse schema requires broodmare_sire_name to be non-null, so a
    -- MANUAL dam must provide both snapshots even though a reference itself
    -- may be intentionally incomplete.
    if v_manual_dam_name is null or v_manual_broodmare_sire_name is null then
      raise exception 'manual dam requires dam name and broodmare sire name'
        using errcode = '23514';
    end if;
    v_dam_name := v_manual_dam_name;
    v_broodmare_sire_name := v_manual_broodmare_sire_name;
  end if;

  -- Keep the authorization marker to the exact structured INSERT only. It is
  -- deliberately cleared before the request ledger and audit writes, so an
  -- ordinary structured Horse INSERT later in this transaction is rejected.
  perform set_config('horserpg.foal_creation_insert', 'on', true);
  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, name_katakana, translated_name,
      sex, coat_color, sire_name, sire_line, dam_name, broodmare_sire_name,
      owner_id, life_stage, sire_parent_source_type, dam_parent_source_type,
      sire_horse_id, dam_horse_id, sire_reference_id, dam_reference_id
    ) values (
      p_horse_number, p_birth_year, v_foal_name, v_name_katakana, v_translated_name,
      v_sex, v_coat_color, v_sire_name, v_sire_line, v_dam_name, v_broodmare_sire_name,
      null, 'FOAL'::public.horse_life_stage, p_sire_source_type, p_dam_source_type,
      p_sire_horse_id, p_dam_horse_id, p_sire_reference_id, p_dam_reference_id
    ) returning * into v_horse;
    perform set_config('horserpg.foal_creation_insert', '', true);
  exception when others then
    perform set_config('horserpg.foal_creation_insert', '', true);
    raise;
  end;

  insert into public.foal_creation_requests (
    request_id, horse_id, request_facts, created_by_user_id
  ) values (
    p_request_id, v_horse.id, v_request_facts, auth.uid()
  );

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, request_id
  ) values (
    auth.uid(), 'GM'::public.app_role, 'FOAL_CREATED', 'horses', v_horse.id::text,
    jsonb_build_object(
      'horse_number', v_horse.horse_number,
      'sire_source_type', v_horse.sire_parent_source_type,
      'dam_source_type', v_horse.dam_parent_source_type,
      'sire_horse_id', v_horse.sire_horse_id,
      'dam_horse_id', v_horse.dam_horse_id,
      'sire_reference_id', v_horse.sire_reference_id,
      'dam_reference_id', v_horse.dam_reference_id
    ), p_request_id
  );

  return v_horse;
end;
$$;

alter table public.breeding_candidates enable row level security;
alter table public.pedigree_reference_horses enable row level security;
alter table public.foal_creation_requests enable row level security;

revoke all on table public.breeding_candidates, public.pedigree_reference_horses,
  public.foal_creation_requests from public, anon, authenticated, service_role;
grant select on table public.breeding_candidates, public.pedigree_reference_horses,
  public.foal_creation_requests to authenticated;

create policy breeding_candidates_select_active_or_gm
on public.breeding_candidates
for select to authenticated
using (public.is_current_user_gm());

create policy pedigree_reference_horses_select_active_or_gm
on public.pedigree_reference_horses
for select to authenticated
using (public.is_current_user_gm());

create policy foal_creation_requests_select_gm
on public.foal_creation_requests
for select to authenticated
using (public.is_current_user_gm());

-- These trusted projections intentionally use the view owner's rights to read
-- only active public material while base-table RLS keeps GM actor metadata,
-- notes, and inactive records unavailable to PLAYER sessions.
create view public.breeding_candidates_public
with (security_barrier = true)
as
select
  candidate.id,
  candidate.horse_id,
  candidate.candidate_type
from public.breeding_candidates as candidate
where candidate.is_active;

create view public.pedigree_reference_horses_public
with (security_barrier = true)
as
select
  reference.id,
  reference.name,
  reference.translated_name,
  reference.sex,
  reference.sire_line,
  reference.sire_name,
  reference.dam_name,
  reference.broodmare_sire_name,
  reference.aliases
from public.pedigree_reference_horses as reference
where reference.is_active;

revoke all on table public.breeding_candidates_public,
  public.pedigree_reference_horses_public from public, anon, authenticated, service_role;
grant select on table public.breeding_candidates_public,
  public.pedigree_reference_horses_public to authenticated;

revoke all on function public.enforce_breeding_candidate_horse_eligibility() from public, anon, authenticated, service_role;
revoke all on function public.prevent_foal_creation_request_mutation() from public, anon, authenticated, service_role;
revoke all on function public.prevent_horse_parent_identity_mutation() from public, anon, authenticated, service_role;
revoke all on function public.horse_canonical_registered_name(public.horses) from public, anon, authenticated, service_role;
revoke all on function public.breeding_candidate_audit_data(public.breeding_candidates) from public, anon, authenticated, service_role;
revoke all on function public.pedigree_reference_horse_audit_data(public.pedigree_reference_horses) from public, anon, authenticated, service_role;
revoke all on function public.activate_breeding_candidate(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.deactivate_breeding_candidate(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.create_pedigree_reference_horse(text, text, text, text, text, text, text, text[], text) from public, anon, authenticated, service_role;
revoke all on function public.update_pedigree_reference_horse(uuid, text, text, text, text, text, text, text, text[], text) from public, anon, authenticated, service_role;
revoke all on function public.deactivate_pedigree_reference_horse(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.create_foal(uuid, bigint, integer, text, text, text, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text) from public, anon, authenticated, service_role;

grant execute on function public.activate_breeding_candidate(uuid, text) to authenticated;
grant execute on function public.deactivate_breeding_candidate(uuid, text) to authenticated;
grant execute on function public.create_pedigree_reference_horse(text, text, text, text, text, text, text, text[], text) to authenticated;
grant execute on function public.update_pedigree_reference_horse(uuid, text, text, text, text, text, text, text, text[], text) to authenticated;
grant execute on function public.deactivate_pedigree_reference_horse(uuid, text) to authenticated;
grant execute on function public.create_foal(uuid, bigint, integer, text, text, text, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text) to authenticated;

comment on table public.breeding_candidates is
  'Current GM-maintained retired breeding candidate identity. It is independent from Horse life_stage and never models a mating event.';
comment on table public.pedigree_reference_horses is
  'Optional external pedigree entry dictionary. Horse snapshots remain independent historical facts after creation.';
comment on table public.foal_creation_requests is
  'Immutable request-id idempotency ledger for controlled Foal creation; it is not a breeding or pregnancy record.';
comment on view public.breeding_candidates_public is
  'Active breeding candidate projection for authenticated users; GM actor metadata and notes remain base-table-only.';
comment on view public.pedigree_reference_horses_public is
  'Active external pedigree reference projection for authenticated users; GM actor metadata and notes remain base-table-only.';
comment on function public.create_foal(uuid, bigint, integer, text, text, text, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text, public.pedigree_parent_source_type, uuid, uuid, text, text) is
  'GM-only idempotent Foal creation. It resolves active internal candidates, active references, or manual snapshots, then creates an unowned FOAL without simulating breeding.';

commit;
