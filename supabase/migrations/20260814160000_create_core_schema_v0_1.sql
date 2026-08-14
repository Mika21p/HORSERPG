-- HorseRPG v0.1 Core schema.
-- This migration intentionally excludes foal trading, public auctions, races,
-- prize receivables, retirement, UI concerns, and any remote Supabase action.

begin;

create type public.app_role as enum ('PLAYER', 'GM');

create type public.horse_life_stage as enum (
  'FOAL',
  'OWNED_FOAL',
  'TRAINING',
  'ACTIVE',
  'RETIRE_PENDING',
  'RETIRED',
  'BREEDING',
  'DISCARDED'
);

create type public.horse_factor_kind as enum ('SIRE', 'MARE');

create type public.injury_status as enum ('ACTIVE', 'RECOVERED', 'CANCELLED');

create table public.owners (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (length(btrim(display_name)) > 0),
  initial_funds bigint not null check (initial_funds >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.user_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.app_role not null,
  owner_id uuid references public.owners(id) on delete restrict,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_profiles_role_owner_binding_check check (
    (role = 'PLAYER'::public.app_role and owner_id is not null)
    or (role = 'GM'::public.app_role and owner_id is null)
  )
);

create unique index user_profiles_one_player_per_owner_idx
  on public.user_profiles (owner_id)
  where owner_id is not null;

create table public.horses (
  id uuid primary key default gen_random_uuid(),
  horse_number bigint not null unique check (horse_number > 0),
  birth_year integer not null check (birth_year > 0),
  foal_name text not null check (length(btrim(foal_name)) > 0),
  name_katakana text,
  translated_name text,
  sex text not null check (sex in ('MALE', 'FEMALE', 'GELDING')),
  coat_color text not null check (length(btrim(coat_color)) > 0),
  sire_name text not null check (length(btrim(sire_name)) > 0),
  sire_line text not null check (length(btrim(sire_line)) > 0),
  broodmare_sire_name text not null check (length(btrim(broodmare_sire_name)) > 0),
  owner_id uuid references public.owners(id) on delete restrict,
  current_jockey_name text,
  current_trainer_name text,
  life_stage public.horse_life_stage not null default 'FOAL'::public.horse_life_stage,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index horses_owner_id_idx on public.horses (owner_id);
create index horses_life_stage_idx on public.horses (life_stage);

create table public.horse_factors (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  factor_kind public.horse_factor_kind not null,
  factor_name text not null check (length(btrim(factor_name)) > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index horse_factors_horse_id_factor_kind_idx
  on public.horse_factors (horse_id, factor_kind);

create table public.financial_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.owners(id) on delete restrict,
  amount bigint not null check (amount <> 0),
  transaction_kind text not null check (length(btrim(transaction_kind)) > 0),
  source_entity_type text,
  source_entity_id uuid,
  effective_at timestamptz not null default now(),
  created_by_user_id uuid references auth.users(id) on delete set null,
  reason text,
  created_at timestamptz not null default now()
);

create index financial_transactions_owner_id_effective_at_idx
  on public.financial_transactions (owner_id, effective_at);

create table public.injuries (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  status public.injury_status not null default 'ACTIVE'::public.injury_status,
  wp_start_year integer not null check (wp_start_year > 0),
  wp_start_month smallint not null check (wp_start_month between 1 and 12),
  wp_start_week smallint not null check (wp_start_week between 1 and 5),
  wp_end_year integer not null check (wp_end_year > 0),
  wp_end_month smallint not null check (wp_end_month between 1 and 12),
  wp_end_week smallint not null check (wp_end_week between 1 and 5),
  notes text,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint injuries_wp_date_order_check check (
    (wp_end_year, wp_end_month, wp_end_week) >= (wp_start_year, wp_start_month, wp_start_week)
  )
);

create index injuries_horse_id_idx on public.injuries (horse_id);

create table public.condition_records (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  wp_year integer not null check (wp_year > 0),
  wp_month smallint not null check (wp_month between 1 and 12),
  wp_week smallint not null check (wp_week between 1 and 5),
  outcome jsonb not null default '{}'::jsonb check (jsonb_typeof(outcome) = 'object'),
  notes text,
  confirmed_by_user_id uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index condition_records_horse_id_wp_time_idx
  on public.condition_records (horse_id, wp_year, wp_month, wp_week);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_role public.app_role not null,
  action text not null check (length(btrim(action)) > 0),
  entity_type text not null check (length(btrim(entity_type)) > 0),
  entity_id text not null check (length(btrim(entity_id)) > 0),
  before_data jsonb,
  after_data jsonb,
  reason text,
  request_id uuid,
  created_at timestamptz not null default now()
);

create index audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
create index audit_logs_actor_created_at_idx on public.audit_logs (actor_user_id, created_at);

-- A boolean singleton key guarantees that this table has zero or one row. It is
-- intentionally left empty until a GM initializes the current WP calendar.
create table public.game_state (
  id boolean primary key default true check (id),
  current_wp_year integer not null check (current_wp_year > 0),
  current_wp_month smallint not null check (current_wp_month between 1 and 12),
  current_wp_week smallint not null check (current_wp_week between 1 and 5),
  updated_by_user_id uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

-- Centralized timestamp maintenance is separate from audit logging. Financial
-- transactions and audit logs use dedicated immutability triggers below instead.
create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger owners_set_updated_at
before update on public.owners
for each row execute function public.set_updated_at();

create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

create trigger horses_set_updated_at
before update on public.horses
for each row execute function public.set_updated_at();

create trigger horse_factors_set_updated_at
before update on public.horse_factors
for each row execute function public.set_updated_at();

create trigger injuries_set_updated_at
before update on public.injuries
for each row execute function public.set_updated_at();

create trigger condition_records_set_updated_at
before update on public.condition_records
for each row execute function public.set_updated_at();

create trigger game_state_set_updated_at
before update on public.game_state
for each row execute function public.set_updated_at();

-- Initial funds are an opening fact. Later corrections must use the immutable ledger.
create function public.prevent_initial_funds_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.initial_funds is distinct from old.initial_funds then
    raise exception 'owners.initial_funds is immutable; use financial_transactions for corrections'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger owners_prevent_initial_funds_update
before update of initial_funds on public.owners
for each row execute function public.prevent_initial_funds_update();

-- Once ownership is assigned, v0.1 does not allow a direct transfer or removal.
-- Future controlled server workflows must use a dedicated, audited procedure rather
-- than granting a client policy that can update ownership.
create function public.prevent_horse_owner_reassignment()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.owner_id is not null and new.owner_id is distinct from old.owner_id then
    raise exception 'horse ownership cannot be reassigned directly'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

create trigger horses_prevent_owner_reassignment
before update of owner_id on public.horses
for each row execute function public.prevent_horse_owner_reassignment();

-- A parent-row lock makes the aggregate factor limit safe under concurrent writes.
create function public.enforce_horse_factor_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  existing_count integer;
begin
  perform 1
  from public.horses
  where id = new.horse_id
  for update;

  select count(*)
  into existing_count
  from public.horse_factors
  where horse_id = new.horse_id
    and factor_kind = new.factor_kind
    and (tg_op = 'INSERT' or id <> new.id);

  if existing_count >= 2 then
    raise exception 'a horse may have at most two factors of each kind'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger horse_factors_enforce_limit
before insert or update of horse_id, factor_kind on public.horse_factors
for each row execute function public.enforce_horse_factor_limit();

-- Financial transactions are immutable ledger facts. The narrow exception is for
-- PostgreSQL's nested ON DELETE SET NULL action when an Auth account is removed;
-- it may only clear the optional actor reference and cannot change money or metadata.
create function public.prevent_financial_transaction_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if pg_trigger_depth() > 1
      and old.created_by_user_id is not null
      and new.created_by_user_id is null
      and new.id is not distinct from old.id
      and new.owner_id is not distinct from old.owner_id
      and new.amount is not distinct from old.amount
      and new.transaction_kind is not distinct from old.transaction_kind
      and new.source_entity_type is not distinct from old.source_entity_type
      and new.source_entity_id is not distinct from old.source_entity_id
      and new.effective_at is not distinct from old.effective_at
      and new.reason is not distinct from old.reason
      and new.created_at is not distinct from old.created_at then
      return new;
    end if;
  end if;

  raise exception 'financial_transactions are append-only; insert a correction transaction instead'
    using errcode = '55000';
end;
$$;

create trigger financial_transactions_prevent_mutation
before update or delete on public.financial_transactions
for each row execute function public.prevent_financial_transaction_mutation();

-- Audit facts are append-only. As above, a nested foreign-key action may only
-- null the deleted Auth account reference while retaining all audit content.
create function public.prevent_audit_log_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    if pg_trigger_depth() > 1
      and old.actor_user_id is not null
      and new.actor_user_id is null
      and new.id is not distinct from old.id
      and new.actor_role is not distinct from old.actor_role
      and new.action is not distinct from old.action
      and new.entity_type is not distinct from old.entity_type
      and new.entity_id is not distinct from old.entity_id
      and new.before_data is not distinct from old.before_data
      and new.after_data is not distinct from old.after_data
      and new.reason is not distinct from old.reason
      and new.request_id is not distinct from old.request_id
      and new.created_at is not distinct from old.created_at then
      return new;
    end if;
  end if;

  raise exception 'audit_logs are append-only'
    using errcode = '55000';
end;
$$;

create trigger audit_logs_prevent_mutation
before update or delete on public.audit_logs
for each row execute function public.prevent_audit_log_mutation();

-- SECURITY DEFINER prevents RLS recursion when a policy determines whether the
-- requesting authenticated user has the GM role. It exposes only a boolean.
create function public.is_current_user_gm()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.user_profiles
    where id = auth.uid()
      and role = 'GM'::public.app_role
  );
$$;

revoke all on function public.is_current_user_gm() from public;
grant execute on function public.is_current_user_gm() to authenticated;

alter table public.user_profiles enable row level security;
alter table public.owners enable row level security;
alter table public.horses enable row level security;
alter table public.horse_factors enable row level security;
alter table public.financial_transactions enable row level security;
alter table public.injuries enable row level security;
alter table public.condition_records enable row level security;
alter table public.audit_logs enable row level security;
alter table public.game_state enable row level security;

-- Explicit grants make the policies effective even when the project's default
-- privileges have not been configured for tables created by migrations.
grant select on public.user_profiles,
  public.owners,
  public.horses,
  public.horse_factors,
  public.financial_transactions,
  public.injuries,
  public.condition_records,
  public.audit_logs,
  public.game_state
to authenticated;

grant insert, update on public.user_profiles,
  public.owners,
  public.horses,
  public.horse_factors,
  public.injuries,
  public.condition_records,
  public.game_state
to authenticated;

grant delete on public.horse_factors to authenticated;

-- Public game records: authenticated PLAYER and GM users may read them.
create policy owners_select_authenticated
on public.owners
for select to authenticated
using (true);

create policy horses_select_authenticated
on public.horses
for select to authenticated
using (true);

create policy horse_factors_select_authenticated
on public.horse_factors
for select to authenticated
using (true);

create policy injuries_select_authenticated
on public.injuries
for select to authenticated
using (true);

create policy condition_records_select_gm
on public.condition_records
for select to authenticated
using (public.is_current_user_gm());

-- Profiles are private to the subject, except that a GM may inspect all profiles.
create policy user_profiles_select_self_or_gm
on public.user_profiles
for select to authenticated
using (id = auth.uid() or public.is_current_user_gm());

-- Only GMs may administer mutable core records through the authenticated API.
-- Normal PLAYER roles receive no write policies for any core table.
create policy user_profiles_write_gm
on public.user_profiles
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy owners_insert_gm
on public.owners
for insert to authenticated
with check (public.is_current_user_gm());

create policy owners_update_gm
on public.owners
for update to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy horses_write_gm
on public.horses
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy horse_factors_write_gm
on public.horse_factors
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy injuries_write_gm
on public.injuries
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

create policy condition_records_write_gm
on public.condition_records
for all to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

-- Ledger and audit rows are server-side append-only facts. There is no client
-- write policy. GMs may inspect them; PLAYER users may not read either table.
create policy financial_transactions_select_gm
on public.financial_transactions
for select to authenticated
using (public.is_current_user_gm());

create policy audit_logs_select_gm
on public.audit_logs
for select to authenticated
using (public.is_current_user_gm());

create policy game_state_select_authenticated
on public.game_state
for select to authenticated
using (true);

create policy game_state_insert_gm
on public.game_state
for insert to authenticated
with check (public.is_current_user_gm());

create policy game_state_update_gm
on public.game_state
for update to authenticated
using (public.is_current_user_gm())
with check (public.is_current_user_gm());

commit;
