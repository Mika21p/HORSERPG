-- HorseRPG v0.4-E Retirement + Prize Release database layer.
-- Retirement is the controlled boundary where pending prize receivables become
-- real append-only Owner ledger facts.  This migration intentionally adds no UI,
-- breeding, injury, fatigue, Realtime, or remote side effects.

-- Do not silently pay a historical row whose retirement provenance cannot be
-- established.  v0.4-D had no controlled retirement path, so this is expected
-- to be empty; a non-empty result needs manual review before deployment.
begin;

do $$
begin
  if exists (
    select 1
    from public.horses as horse
    join public.prize_receivables as receivable
      on receivable.horse_id = horse.id
    where horse.life_stage = 'RETIRED'::public.horse_life_stage
      and receivable.status = 'PENDING'::public.prize_receivable_status
  ) then
    raise exception 'manual review required before v0.4-E: RETIRED Horse has PENDING prize receivable'
      using errcode = '23514';
  end if;
end;
$$;

commit;

-- PostgreSQL does not permit a newly-added enum value to be used until the
-- transaction that adds it has committed.  Keep this as a separate safe step.
alter type public.prize_receivable_status add value if not exists 'RELEASED';

begin;

create type public.horse_retirement_request_kind as enum (
  'OWNER_REQUEST',
  'G1_LIMIT',
  'WP_LIFESPAN'
);

create type public.horse_retirement_request_status as enum (
  'PENDING',
  'CONFIRMED',
  'REJECTED',
  'WITHDRAWN'
);

create type public.prize_receivable_ledger_entry_kind as enum (
  'RELEASE',
  'CORRECTION_ADJUSTMENT',
  'VOID_REVERSAL'
);

create table public.horse_retirement_requests (
  id uuid primary key default gen_random_uuid(),
  horse_id uuid not null references public.horses(id) on delete restrict,
  -- Owner at request creation is an immutable historical snapshot.
  owner_id uuid not null references public.owners(id) on delete restrict,
  request_kind public.horse_retirement_request_kind not null,
  status public.horse_retirement_request_status not null default 'PENDING'::public.horse_retirement_request_status,
  player_note text check (player_note is null or length(btrim(player_note)) > 0),
  gm_reason text check (gm_reason is null or length(btrim(gm_reason)) > 0),
  requested_by_user_id uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default clock_timestamp(),
  reviewed_by_user_id uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  withdrawn_by_user_id uuid references auth.users(id) on delete set null,
  withdrawn_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  constraint horse_retirement_requests_status_state_check check (
    (
      status = 'PENDING'::public.horse_retirement_request_status
      and reviewed_at is null
      and withdrawn_at is null
      and completed_at is null
    )
    or
    (
      status = 'CONFIRMED'::public.horse_retirement_request_status
      and reviewed_at is not null
      and withdrawn_at is null
      and completed_at is not null
    )
    or
    (
      status = 'REJECTED'::public.horse_retirement_request_status
      and reviewed_at is not null
      and withdrawn_at is null
      and completed_at is null
      and gm_reason is not null
      and length(btrim(gm_reason)) > 0
    )
    or
    (
      status = 'WITHDRAWN'::public.horse_retirement_request_status
      and reviewed_at is null
      and withdrawn_at is not null
      and completed_at is null
    )
  ),
  constraint horse_retirement_requests_wp_lifespan_reason_check check (
    request_kind <> 'WP_LIFESPAN'::public.horse_retirement_request_kind
    or (gm_reason is not null and length(btrim(gm_reason)) > 0)
  )
);

create unique index horse_retirement_requests_one_pending_per_horse_idx
  on public.horse_retirement_requests (horse_id)
  where status = 'PENDING'::public.horse_retirement_request_status;

create unique index horse_retirement_requests_one_confirmed_per_horse_idx
  on public.horse_retirement_requests (horse_id)
  where status = 'CONFIRMED'::public.horse_retirement_request_status;

create index horse_retirement_requests_owner_status_idx
  on public.horse_retirement_requests (owner_id, status, requested_at desc);

create index horse_retirement_requests_horse_requested_at_idx
  on public.horse_retirement_requests (horse_id, requested_at desc);

alter table public.prize_receivables
  add column released_at timestamptz,
  add column release_retirement_request_id uuid references public.horse_retirement_requests(id) on delete restrict;

alter table public.prize_receivables
  drop constraint prize_receivables_cancellation_state_check,
  add constraint prize_receivables_cancellation_state_check check (
    (
      status = 'PENDING'::public.prize_receivable_status
      and released_at is null
      and cancelled_at is null
      and cancellation_reason is null
    )
    or
    (
      status = 'RELEASED'::public.prize_receivable_status
      and released_at is not null
      and release_retirement_request_id is not null
      and cancelled_at is null
      and cancellation_reason is null
    )
    or
    (
      status = 'CANCELLED'::public.prize_receivable_status
      and cancelled_at is not null
      and cancellation_reason is not null
      and length(btrim(cancellation_reason)) > 0
    )
  );

create index prize_receivables_pending_horse_id_idx
  on public.prize_receivables (horse_id, id)
  where status = 'PENDING'::public.prize_receivable_status;

create table public.prize_receivable_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  prize_receivable_id uuid not null references public.prize_receivables(id) on delete restrict,
  retirement_request_id uuid not null references public.horse_retirement_requests(id) on delete restrict,
  entry_kind public.prize_receivable_ledger_entry_kind not null,
  amount_delta bigint not null,
  financial_transaction_id uuid unique references public.financial_transactions(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  reason text check (reason is null or length(btrim(reason)) > 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint prize_receivable_ledger_entries_financial_link_check check (
    (amount_delta = 0 and financial_transaction_id is null)
    or (amount_delta <> 0 and financial_transaction_id is not null)
  ),
  constraint prize_receivable_ledger_entries_non_release_nonzero_check check (
    entry_kind <> 'CORRECTION_ADJUSTMENT'::public.prize_receivable_ledger_entry_kind
    or amount_delta <> 0
  )
);

create unique index prize_receivable_ledger_entries_one_release_idx
  on public.prize_receivable_ledger_entries (prize_receivable_id)
  where entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind;

create index prize_receivable_ledger_entries_receivable_created_at_idx
  on public.prize_receivable_ledger_entries (prize_receivable_id, created_at, id);

create unique index financial_transactions_prize_ledger_source_once_idx
  on public.financial_transactions (source_entity_type, source_entity_id)
  where source_entity_type = 'PRIZE_RECEIVABLE_LEDGER_ENTRY';

create trigger horse_retirement_requests_set_updated_at
before update on public.horse_retirement_requests
for each row execute function public.set_updated_at();

create function public.prevent_horse_retirement_request_identity_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.horse_id is distinct from old.horse_id
    or new.owner_id is distinct from old.owner_id
    or new.request_kind is distinct from old.request_kind then
    raise exception 'a horse retirement request cannot be moved or have its kind changed'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger horse_retirement_requests_prevent_identity_mutation
before update of horse_id, owner_id, request_kind on public.horse_retirement_requests
for each row execute function public.prevent_horse_retirement_request_identity_mutation();

-- Retirement state changes are intentionally unavailable to normal Horse CRUD.
-- The five trusted retirement RPCs set this transaction-local marker.
create function public.enforce_retirement_horse_lifecycle()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    (tg_op = 'INSERT'
      and new.life_stage in (
        'RETIRE_PENDING'::public.horse_life_stage,
        'RETIRED'::public.horse_life_stage
      ))
    or
    (tg_op = 'UPDATE'
      and old.life_stage is distinct from new.life_stage
      and (
        old.life_stage in (
          'RETIRE_PENDING'::public.horse_life_stage,
          'RETIRED'::public.horse_life_stage
        )
        or new.life_stage in (
          'RETIRE_PENDING'::public.horse_life_stage,
          'RETIRED'::public.horse_life_stage
        )
      ))
  ) and current_setting('horserpg.retirement_transition', true) is distinct from 'on' then
    raise exception 'retirement Horse lifecycle changes require a controlled retirement operation'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

create trigger horses_enforce_retirement_lifecycle
before insert or update on public.horses
for each row execute function public.enforce_retirement_horse_lifecycle();

create function public.prevent_prize_receivable_ledger_entry_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and pg_trigger_depth() > 1
    and old.actor_user_id is not null
    and new.actor_user_id is null
    and new.id is not distinct from old.id
    and new.prize_receivable_id is not distinct from old.prize_receivable_id
    and new.retirement_request_id is not distinct from old.retirement_request_id
    and new.entry_kind is not distinct from old.entry_kind
    and new.amount_delta is not distinct from old.amount_delta
    and new.financial_transaction_id is not distinct from old.financial_transaction_id
    and new.reason is not distinct from old.reason
    and new.created_at is not distinct from old.created_at then
    return new;
  end if;

  raise exception 'prize_receivable_ledger_entries are append-only'
    using errcode = '55000';
end;
$$;

create trigger prize_receivable_ledger_entries_prevent_mutation
before update or delete on public.prize_receivable_ledger_entries
for each row execute function public.prevent_prize_receivable_ledger_entry_mutation();

create or replace function public.prize_receivable_audit_data(
  p_prize_receivable public.prize_receivables
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_prize_receivable.id,
    'race_result_id', p_prize_receivable.race_result_id,
    'horse_id', p_prize_receivable.horse_id,
    'owner_id', p_prize_receivable.owner_id,
    'amount', p_prize_receivable.amount,
    'status', p_prize_receivable.status,
    'released_at', p_prize_receivable.released_at,
    'release_retirement_request_id', p_prize_receivable.release_retirement_request_id,
    'cancelled_at', p_prize_receivable.cancelled_at,
    'cancellation_reason', p_prize_receivable.cancellation_reason
  );
$$;

create function public.horse_retirement_request_audit_data(
  p_request public.horse_retirement_requests
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p_request.id,
    'horse_id', p_request.horse_id,
    'owner_id', p_request.owner_id,
    'request_kind', p_request.request_kind,
    'status', p_request.status,
    'player_note', p_request.player_note,
    'gm_reason', p_request.gm_reason,
    'requested_at', p_request.requested_at,
    'reviewed_at', p_request.reviewed_at,
    'withdrawn_at', p_request.withdrawn_at,
    'completed_at', p_request.completed_at
  );
$$;

-- Prize identity comes from its immutable Result and Confirmed Entry.  This
-- deliberately uses non-locking reads: result correction/void first locks its
-- Result then joins the shared Horse lock in the sync trigger, while retirement
-- first locks its Horse.  Taking a Result row lock here would invert that order.
create or replace function public.enforce_prize_receivable_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.race_results%rowtype;
  v_entry_owner_id uuid;
  v_horse_life_stage public.horse_life_stage;
begin
  if tg_op = 'UPDATE'
    and (
      new.race_result_id is distinct from old.race_result_id
      or new.horse_id is distinct from old.horse_id
      or new.owner_id is distinct from old.owner_id
    ) then
    raise exception 'a prize receivable cannot be moved to another Race Result, Horse, or Owner'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
    and old.status = 'CANCELLED'::public.prize_receivable_status
    and new.status <> old.status then
    raise exception 'a cancelled prize receivable cannot return to pending or released'
      using errcode = '23514';
  end if;

  if tg_op = 'UPDATE'
    and old.released_at is not null
    and (
      new.released_at is distinct from old.released_at
      or new.release_retirement_request_id is distinct from old.release_retirement_request_id
    ) then
    raise exception 'a prize receivable release identity is immutable'
      using errcode = '23514';
  end if;

  select *
  into v_result
  from public.race_results
  where id = new.race_result_id;

  if not found then
    raise exception 'a prize receivable requires an existing Race Result'
      using errcode = '23503';
  end if;

  select owner_id
  into v_entry_owner_id
  from public.confirmed_race_entries
  where id = v_result.confirmed_race_entry_id;

  if not found then
    raise exception 'a prize receivable Race Result requires an existing Confirmed Entry'
      using errcode = '23503';
  end if;

  if new.horse_id <> v_result.horse_id
    or new.owner_id <> v_entry_owner_id
    or new.amount <> v_result.prize_amount then
    raise exception 'a prize receivable must match its Race Result Horse, Confirmed Entry Owner, and prize amount'
      using errcode = '23514';
  end if;

  if v_result.status = 'CONFIRMED'::public.race_result_status then
    if new.status not in (
      'PENDING'::public.prize_receivable_status,
      'RELEASED'::public.prize_receivable_status
    ) then
      raise exception 'a confirmed Race Result requires a PENDING or RELEASED prize receivable'
        using errcode = '23514';
    end if;
  elsif new.status <> 'CANCELLED'::public.prize_receivable_status then
    raise exception 'a VOIDED Race Result requires a CANCELLED prize receivable'
      using errcode = '23514';
  end if;

  if new.status = 'PENDING'::public.prize_receivable_status then
    if new.released_at is not null or new.release_retirement_request_id is not null then
      raise exception 'a pending prize receivable cannot have release facts'
        using errcode = '23514';
    end if;
  elsif new.status = 'RELEASED'::public.prize_receivable_status then
    select life_stage
    into v_horse_life_stage
    from public.horses
    where id = new.horse_id;

    if v_horse_life_stage <> 'RETIRED'::public.horse_life_stage
      or not exists (
        select 1
        from public.prize_receivable_ledger_entries as ledger_entry
        where ledger_entry.prize_receivable_id = new.id
          and ledger_entry.entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind
      ) then
      raise exception 'a RELEASED prize receivable requires a retired Horse and one release ledger entry'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

-- Ledger insertion validates the exact financial amount and Owner against the
-- immutable receivable.  Only trusted helpers set the transaction-local flag.
create function public.enforce_prize_receivable_ledger_entry_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receivable public.prize_receivables%rowtype;
  v_request public.horse_retirement_requests%rowtype;
  v_result public.race_results%rowtype;
  v_horse_life_stage public.horse_life_stage;
  v_transaction public.financial_transactions%rowtype;
  v_expected_kind text;
begin
  if current_setting('horserpg.prize_ledger_write', true) is distinct from 'on' then
    raise exception 'prize receivable ledger entries require a controlled prize operation'
      using errcode = '42501';
  end if;

  select * into v_receivable
  from public.prize_receivables
  where id = new.prize_receivable_id;

  if not found then
    raise exception 'prize ledger entry requires an existing prize receivable'
      using errcode = '23503';
  end if;

  select * into v_request
  from public.horse_retirement_requests
  where id = new.retirement_request_id;

  if not found
    or v_request.horse_id <> v_receivable.horse_id
    or v_request.status <> 'CONFIRMED'::public.horse_retirement_request_status then
    raise exception 'prize ledger entry requires the Horse''s confirmed retirement request'
      using errcode = '23514';
  end if;

  select life_stage into v_horse_life_stage
  from public.horses
  where id = v_receivable.horse_id;

  if v_horse_life_stage <> 'RETIRED'::public.horse_life_stage then
    raise exception 'prize ledger entry requires a RETIRED Horse'
      using errcode = '23514';
  end if;

  select * into v_result
  from public.race_results
  where id = v_receivable.race_result_id;

  if not found then
    raise exception 'prize ledger entry requires an existing Race Result'
      using errcode = '23503';
  end if;

  if new.entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind then
    if v_receivable.status <> 'PENDING'::public.prize_receivable_status
      or new.amount_delta <> v_receivable.amount then
      raise exception 'a prize release must exactly release one pending receivable amount'
        using errcode = '23514';
    end if;
    v_expected_kind := 'PRIZE_RELEASE';
  elsif new.entry_kind = 'CORRECTION_ADJUSTMENT'::public.prize_receivable_ledger_entry_kind then
    if v_receivable.status <> 'RELEASED'::public.prize_receivable_status
      or v_result.status <> 'CONFIRMED'::public.race_result_status
      or new.retirement_request_id <> v_receivable.release_retirement_request_id
      or new.amount_delta <> v_result.prize_amount - v_receivable.amount then
      raise exception 'a prize correction ledger entry must equal the released receivable delta'
        using errcode = '23514';
    end if;
    v_expected_kind := 'PRIZE_CORRECTION';
  else
    if v_receivable.status <> 'RELEASED'::public.prize_receivable_status
      or v_result.status <> 'VOIDED'::public.race_result_status
      or new.retirement_request_id <> v_receivable.release_retirement_request_id
      or new.amount_delta <> -v_receivable.amount then
      raise exception 'a prize void reversal must negate the released receivable amount'
        using errcode = '23514';
    end if;
    v_expected_kind := 'PRIZE_VOID_REVERSAL';
  end if;

  if new.amount_delta = 0 then
    if new.financial_transaction_id is not null then
      raise exception 'a zero prize ledger entry cannot reference a financial transaction'
        using errcode = '23514';
    end if;
  else
    select * into v_transaction
    from public.financial_transactions
    where id = new.financial_transaction_id;

    if not found
      or v_transaction.owner_id <> v_receivable.owner_id
      or v_transaction.amount <> new.amount_delta
      or v_transaction.transaction_kind <> v_expected_kind
      or v_transaction.source_entity_type <> 'PRIZE_RECEIVABLE_LEDGER_ENTRY'
      or v_transaction.source_entity_id <> new.id then
      raise exception 'a prize ledger financial transaction must match its receivable, delta, kind, and source entry'
        using errcode = '23514';
    end if;
  end if;

  return new;
end;
$$;

create trigger prize_receivable_ledger_entries_enforce_integrity
before insert on public.prize_receivable_ledger_entries
for each row execute function public.enforce_prize_receivable_ledger_entry_integrity();

-- Deferred cross-table guard: temporary PENDING rows are permitted inside the
-- same trusted transaction so a late result can be inserted then immediately
-- released, but no commit may leave a RETIRED Horse with PENDING prize money.
create function public.enforce_no_pending_prizes_for_retired_horse()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse_id uuid;
begin
  if tg_table_name = 'horses' then
    if tg_op = 'DELETE' then
      v_horse_id := old.id;
    else
      v_horse_id := new.id;
    end if;
  else
    if tg_op = 'DELETE' then
      v_horse_id := old.horse_id;
    else
      v_horse_id := new.horse_id;
    end if;
  end if;

  if exists (
    select 1
    from public.horses as horse
    join public.prize_receivables as receivable
      on receivable.horse_id = horse.id
    where horse.id = v_horse_id
      and horse.life_stage = 'RETIRED'::public.horse_life_stage
      and receivable.status = 'PENDING'::public.prize_receivable_status
  ) then
    raise exception 'a RETIRED Horse cannot retain a PENDING prize receivable'
      using errcode = '23514';
  end if;

  return null;
end;
$$;

create constraint trigger horses_enforce_no_pending_prizes_when_retired
after update of life_stage on public.horses
deferrable initially deferred
for each row execute function public.enforce_no_pending_prizes_for_retired_horse();

create constraint trigger prize_receivables_enforce_no_pending_for_retired_horse
after insert or update or delete on public.prize_receivables
deferrable initially deferred
for each row execute function public.enforce_no_pending_prizes_for_retired_horse();

create function public.append_prize_receivable_ledger_entry(
  p_prize_receivable_id uuid,
  p_retirement_request_id uuid,
  p_entry_kind public.prize_receivable_ledger_entry_kind,
  p_amount_delta bigint,
  p_actor_user_id uuid,
  p_reason text default null
)
returns public.prize_receivable_ledger_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_entry_id uuid := gen_random_uuid();
  v_financial_transaction_id uuid;
  v_entry public.prize_receivable_ledger_entries%rowtype;
  v_transaction_kind text;
  v_reason text := nullif(btrim(p_reason), '');
begin
  if auth.uid() is null
    or p_actor_user_id is null
    or p_actor_user_id <> auth.uid()
    or not public.is_current_user_gm() then
    raise exception 'only the current GM may write a prize ledger entry'
      using errcode = '42501';
  end if;

  if p_amount_delta is null then
    raise exception 'a prize ledger amount delta is required'
      using errcode = '23514';
  end if;

  if p_entry_kind = 'RELEASE'::public.prize_receivable_ledger_entry_kind then
    v_transaction_kind := 'PRIZE_RELEASE';
  elsif p_entry_kind = 'CORRECTION_ADJUSTMENT'::public.prize_receivable_ledger_entry_kind then
    v_transaction_kind := 'PRIZE_CORRECTION';
  else
    v_transaction_kind := 'PRIZE_VOID_REVERSAL';
  end if;

  if p_amount_delta <> 0 then
    insert into public.financial_transactions (
      owner_id,
      amount,
      transaction_kind,
      source_entity_type,
      source_entity_id,
      created_by_user_id,
      reason
    )
    select
      receivable.owner_id,
      p_amount_delta,
      v_transaction_kind,
      'PRIZE_RECEIVABLE_LEDGER_ENTRY',
      v_entry_id,
      p_actor_user_id,
      v_reason
    from public.prize_receivables as receivable
    where receivable.id = p_prize_receivable_id
    returning id into v_financial_transaction_id;

    if v_financial_transaction_id is null then
      raise exception 'prize receivable does not exist while creating a ledger transaction'
        using errcode = '23503';
    end if;
  end if;

  perform set_config('horserpg.prize_ledger_write', 'on', true);

  insert into public.prize_receivable_ledger_entries (
    id,
    prize_receivable_id,
    retirement_request_id,
    entry_kind,
    amount_delta,
    financial_transaction_id,
    actor_user_id,
    reason
  ) values (
    v_entry_id,
    p_prize_receivable_id,
    p_retirement_request_id,
    p_entry_kind,
    p_amount_delta,
    v_financial_transaction_id,
    p_actor_user_id,
    v_reason
  ) returning * into v_entry;

  return v_entry;
end;
$$;

create function public.release_prize_receivable(
  p_prize_receivable_id uuid,
  p_retirement_request_id uuid,
  p_actor_user_id uuid,
  p_reason text default null
)
returns public.prize_receivables
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse_id uuid;
  v_horse public.horses%rowtype;
  v_request public.horse_retirement_requests%rowtype;
  v_receivable public.prize_receivables%rowtype;
  v_ledger public.prize_receivable_ledger_entries%rowtype;
  v_now timestamptz := clock_timestamp();
begin
  if auth.uid() is null
    or p_actor_user_id is null
    or p_actor_user_id <> auth.uid()
    or not public.is_current_user_gm() then
    raise exception 'only the current GM may release a prize receivable'
      using errcode = '42501';
  end if;

  -- Discover first without a row lock, then take the globally shared Horse
  -- lock before the receivable lock.  Result sync follows the same order.
  select horse_id into v_horse_id
  from public.prize_receivables
  where id = p_prize_receivable_id;

  if v_horse_id is null then
    raise exception 'prize receivable does not exist'
      using errcode = '23503';
  end if;

  select * into v_horse
  from public.horses
  where id = v_horse_id
  for update;

  select * into v_receivable
  from public.prize_receivables
  where id = p_prize_receivable_id
  for update;

  if v_receivable.status = 'RELEASED'::public.prize_receivable_status then
    if v_receivable.release_retirement_request_id = p_retirement_request_id then
      return v_receivable;
    end if;

    raise exception 'prize receivable is already released by another retirement request'
      using errcode = '23514';
  end if;

  if v_receivable.status <> 'PENDING'::public.prize_receivable_status then
    raise exception 'only a pending prize receivable may be released'
      using errcode = '23514';
  end if;

  select * into v_request
  from public.horse_retirement_requests
  where id = p_retirement_request_id;

  if not found
    or v_request.horse_id <> v_receivable.horse_id
    or v_request.status <> 'CONFIRMED'::public.horse_retirement_request_status
    or v_horse.life_stage <> 'RETIRED'::public.horse_life_stage then
    raise exception 'prize release requires its Horse''s confirmed retirement'
      using errcode = '23514';
  end if;

  select * into v_ledger
  from public.append_prize_receivable_ledger_entry(
    v_receivable.id,
    v_request.id,
    'RELEASE'::public.prize_receivable_ledger_entry_kind,
    v_receivable.amount,
    p_actor_user_id,
    coalesce(nullif(btrim(p_reason), ''), 'Prize release at Horse retirement')
  );

  update public.prize_receivables
  set status = 'RELEASED'::public.prize_receivable_status,
      released_at = v_now,
      release_retirement_request_id = v_request.id
  where id = v_receivable.id
  returning * into v_receivable;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    p_actor_user_id,
    'GM'::public.app_role,
    'PRIZE_RECEIVABLE_RELEASED',
    'prize_receivables',
    v_receivable.id::text,
    jsonb_build_object(
      'receivable_id', v_receivable.id,
      'race_result_id', v_receivable.race_result_id,
      'horse_id', v_receivable.horse_id,
      'owner_id', v_receivable.owner_id,
      'amount', v_receivable.amount,
      'retirement_request_id', v_request.id,
      'financial_transaction_id', v_ledger.financial_transaction_id,
      'released_at', v_receivable.released_at
    ),
    v_ledger.reason
  );

  return v_receivable;
end;
$$;

create function public.release_pending_prizes_for_horse(
  p_horse_id uuid,
  p_retirement_request_id uuid,
  p_actor_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_receivable record;
begin
  for v_receivable in
    select id
    from public.prize_receivables
    where horse_id = p_horse_id
      and status = 'PENDING'::public.prize_receivable_status
    order by id
    for update
  loop
    perform public.release_prize_receivable(
      v_receivable.id,
      p_retirement_request_id,
      p_actor_user_id,
      'Prize release at Horse retirement'
    );
  end loop;
end;
$$;

create function public.submit_horse_retirement_request(
  p_horse_id uuid,
  p_player_note text default null
)
returns public.horse_retirement_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_horse public.horses%rowtype;
  v_existing public.horse_retirement_requests%rowtype;
  v_request public.horse_retirement_requests%rowtype;
  v_note text := nullif(btrim(p_player_note), '');
  v_game_state public.game_state%rowtype;
begin
  select profile.owner_id into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null;

  if auth.uid() is null or v_owner_id is null then
    raise exception 'only a PLAYER with an Owner may request Horse retirement'
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

  if v_horse.owner_id is distinct from v_owner_id then
    raise exception 'a PLAYER may request retirement only for that PLAYER Owner''s Horse'
      using errcode = '42501';
  end if;

  select * into v_existing
  from public.horse_retirement_requests
  where horse_id = v_horse.id
    and status = 'PENDING'::public.horse_retirement_request_status
  for update;

  if found then
    if v_existing.owner_id = v_owner_id
      and v_existing.request_kind = 'OWNER_REQUEST'::public.horse_retirement_request_kind
      and v_existing.player_note is not distinct from v_note then
      return v_existing;
    end if;

    raise exception 'Horse already has a different pending retirement request'
      using errcode = '23505';
  end if;

  if v_horse.life_stage <> 'ACTIVE'::public.horse_life_stage then
    raise exception 'only an ACTIVE Horse may receive a retirement request'
      using errcode = '23514';
  end if;

  select * into v_game_state
  from public.game_state
  for share;

  if not found then
    raise exception 'game state must be initialized before Horse retirement can be requested'
      using errcode = '23514';
  end if;

  if v_game_state.current_wp_year - v_horse.birth_year < 3 then
    raise exception 'an Owner retirement request requires a Horse aged at least 3 WP years'
      using errcode = '23514';
  end if;

  insert into public.horse_retirement_requests (
    horse_id, owner_id, request_kind, player_note, requested_by_user_id
  ) values (
    v_horse.id, v_owner_id, 'OWNER_REQUEST'::public.horse_retirement_request_kind,
    v_note, auth.uid()
  ) returning * into v_request;

  perform set_config('horserpg.retirement_transition', 'on', true);
  update public.horses
  set life_stage = 'RETIRE_PENDING'::public.horse_life_stage
  where id = v_horse.id;
  perform set_config('horserpg.retirement_transition', 'off', true);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data
  ) values (
    auth.uid(), 'PLAYER'::public.app_role, 'HORSE_RETIREMENT_REQUESTED',
    'horse_retirement_requests', v_request.id::text,
    public.horse_retirement_request_audit_data(v_request)
  );

  return v_request;
end;
$$;

create function public.withdraw_horse_retirement_request(
  p_request_id uuid
)
returns public.horse_retirement_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_request public.horse_retirement_requests%rowtype;
  v_horse public.horses%rowtype;
  v_before jsonb;
begin
  select profile.owner_id into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null;

  if auth.uid() is null or v_owner_id is null then
    raise exception 'only a PLAYER with an Owner may withdraw a retirement request'
      using errcode = '42501';
  end if;

  select * into v_request
  from public.horse_retirement_requests
  where id = p_request_id
  for update;

  if not found or v_request.owner_id <> v_owner_id
    or v_request.request_kind <> 'OWNER_REQUEST'::public.horse_retirement_request_kind then
    raise exception 'a PLAYER may withdraw only that PLAYER Owner''s pending retirement request'
      using errcode = '42501';
  end if;

  if v_request.status = 'WITHDRAWN'::public.horse_retirement_request_status then
    return v_request;
  end if;

  if v_request.status <> 'PENDING'::public.horse_retirement_request_status then
    raise exception 'only a pending Owner retirement request may be withdrawn'
      using errcode = '23514';
  end if;

  select * into v_horse
  from public.horses
  where id = v_request.horse_id
  for update;

  if not found or v_horse.life_stage <> 'RETIRE_PENDING'::public.horse_life_stage then
    raise exception 'pending retirement request Horse is not RETIRE_PENDING'
      using errcode = '23514';
  end if;

  v_before := public.horse_retirement_request_audit_data(v_request);
  update public.horse_retirement_requests
  set status = 'WITHDRAWN'::public.horse_retirement_request_status,
      withdrawn_by_user_id = auth.uid(),
      withdrawn_at = clock_timestamp()
  where id = v_request.id
  returning * into v_request;

  perform set_config('horserpg.retirement_transition', 'on', true);
  update public.horses
  set life_stage = 'ACTIVE'::public.horse_life_stage
  where id = v_horse.id;
  perform set_config('horserpg.retirement_transition', 'off', true);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'PLAYER'::public.app_role, 'HORSE_RETIREMENT_WITHDRAWN',
    'horse_retirement_requests', v_request.id::text,
    v_before, public.horse_retirement_request_audit_data(v_request)
  );

  return v_request;
end;
$$;

create function public.create_gm_retirement_request(
  p_horse_id uuid,
  p_request_kind public.horse_retirement_request_kind,
  p_gm_reason text default null
)
returns public.horse_retirement_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_horse public.horses%rowtype;
  v_existing public.horse_retirement_requests%rowtype;
  v_request public.horse_retirement_requests%rowtype;
  v_reason text := nullif(btrim(p_gm_reason), '');
  v_g1_wins integer;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may create a forced retirement request'
      using errcode = '42501';
  end if;

  if p_request_kind not in (
    'G1_LIMIT'::public.horse_retirement_request_kind,
    'WP_LIFESPAN'::public.horse_retirement_request_kind
  ) then
    raise exception 'GM retirement requests must use G1_LIMIT or WP_LIFESPAN'
      using errcode = '23514';
  end if;

  if p_request_kind = 'WP_LIFESPAN'::public.horse_retirement_request_kind
    and v_reason is null then
    raise exception 'WP_LIFESPAN retirement requires a GM reason'
      using errcode = '23514';
  end if;

  select * into v_horse
  from public.horses
  where id = p_horse_id
  for update;

  if not found or v_horse.owner_id is null then
    raise exception 'forced retirement requires an existing owned Horse'
      using errcode = '23514';
  end if;

  select * into v_existing
  from public.horse_retirement_requests
  where horse_id = v_horse.id
    and status = 'PENDING'::public.horse_retirement_request_status
  for update;

  if found then
    if v_existing.request_kind = p_request_kind
      and v_existing.gm_reason is not distinct from v_reason then
      return v_existing;
    end if;

    raise exception 'Horse already has a different pending retirement request'
      using errcode = '23505';
  end if;

  if v_horse.life_stage <> 'ACTIVE'::public.horse_life_stage then
    raise exception 'only an ACTIVE Horse may receive a forced retirement request'
      using errcode = '23514';
  end if;

  if p_request_kind = 'G1_LIMIT'::public.horse_retirement_request_kind then
    select count(*) into v_g1_wins
    from public.race_results as result
    join public.actual_races as actual_race
      on actual_race.id = result.actual_race_id
    where result.horse_id = v_horse.id
      and result.status = 'CONFIRMED'::public.race_result_status
      and result.finish_position = 1
      and actual_race.grade = 'G1'::public.race_catalog_grade;

    if v_g1_wins < 9 then
      raise exception 'G1_LIMIT retirement requires at least 9 current G1 wins'
        using errcode = '23514';
    end if;
  end if;

  insert into public.horse_retirement_requests (
    horse_id, owner_id, request_kind, gm_reason, requested_by_user_id
  ) values (
    v_horse.id, v_horse.owner_id, p_request_kind, v_reason, auth.uid()
  ) returning * into v_request;

  perform set_config('horserpg.retirement_transition', 'on', true);
  update public.horses
  set life_stage = 'RETIRE_PENDING'::public.horse_life_stage
  where id = v_horse.id;
  perform set_config('horserpg.retirement_transition', 'off', true);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'HORSE_RETIREMENT_FORCED_PENDING',
    'horse_retirement_requests', v_request.id::text,
    public.horse_retirement_request_audit_data(v_request), v_reason
  );

  return v_request;
end;
$$;

create function public.reject_horse_retirement_request(
  p_request_id uuid,
  p_reason text
)
returns public.horse_retirement_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.horse_retirement_requests%rowtype;
  v_horse public.horses%rowtype;
  v_reason text := nullif(btrim(p_reason), '');
  v_before jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may reject a retirement request'
      using errcode = '42501';
  end if;

  if v_reason is null then
    raise exception 'retirement rejection reason is required'
      using errcode = '23514';
  end if;

  select * into v_request
  from public.horse_retirement_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'retirement request does not exist'
      using errcode = 'P0001';
  end if;

  if v_request.status = 'REJECTED'::public.horse_retirement_request_status then
    if v_request.gm_reason = v_reason then
      return v_request;
    end if;

    raise exception 'a rejected retirement request cannot have its reason changed'
      using errcode = '23514';
  end if;

  if v_request.status <> 'PENDING'::public.horse_retirement_request_status then
    raise exception 'only a pending retirement request may be rejected'
      using errcode = '23514';
  end if;

  select * into v_horse
  from public.horses
  where id = v_request.horse_id
  for update;

  if not found or v_horse.life_stage <> 'RETIRE_PENDING'::public.horse_life_stage then
    raise exception 'pending retirement request Horse is not RETIRE_PENDING'
      using errcode = '23514';
  end if;

  v_before := public.horse_retirement_request_audit_data(v_request);
  update public.horse_retirement_requests
  set status = 'REJECTED'::public.horse_retirement_request_status,
      gm_reason = v_reason,
      reviewed_by_user_id = auth.uid(),
      reviewed_at = clock_timestamp()
  where id = v_request.id
  returning * into v_request;

  perform set_config('horserpg.retirement_transition', 'on', true);
  update public.horses
  set life_stage = 'ACTIVE'::public.horse_life_stage
  where id = v_horse.id;
  perform set_config('horserpg.retirement_transition', 'off', true);

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'HORSE_RETIREMENT_REJECTED',
    'horse_retirement_requests', v_request.id::text,
    v_before, public.horse_retirement_request_audit_data(v_request), v_reason
  );

  return v_request;
end;
$$;

create function public.confirm_horse_retirement(
  p_request_id uuid
)
returns public.horse_retirement_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.horse_retirement_requests%rowtype;
  v_horse public.horses%rowtype;
  v_game_state public.game_state%rowtype;
  v_before jsonb;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM may confirm Horse retirement'
      using errcode = '42501';
  end if;

  -- Request is the retry serial point.  A completed transaction never
  -- re-enters release work or emits duplicate financial/audit history.
  select * into v_request
  from public.horse_retirement_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'retirement request does not exist'
      using errcode = 'P0001';
  end if;

  if v_request.status = 'CONFIRMED'::public.horse_retirement_request_status then
    return v_request;
  end if;

  if v_request.status <> 'PENDING'::public.horse_retirement_request_status then
    raise exception 'only a pending retirement request may be confirmed'
      using errcode = '23514';
  end if;

  select * into v_horse
  from public.horses
  where id = v_request.horse_id
  for update;

  if not found or v_horse.life_stage <> 'RETIRE_PENDING'::public.horse_life_stage then
    raise exception 'pending retirement request Horse is not RETIRE_PENDING'
      using errcode = '23514';
  end if;

  select * into v_game_state
  from public.game_state
  for share;

  if not found then
    raise exception 'game state must be initialized before Horse retirement can be confirmed'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.confirmed_race_entries as entry
    where entry.horse_id = v_horse.id
      and (entry.wp_year, entry.wp_month, entry.wp_week)
        > (v_game_state.current_wp_year, v_game_state.current_wp_month, v_game_state.current_wp_week)
  ) then
    raise exception 'Horse has future confirmed race entries.'
      using errcode = '23514';
  end if;

  v_before := public.horse_retirement_request_audit_data(v_request);
  update public.horse_retirement_requests
  set status = 'CONFIRMED'::public.horse_retirement_request_status,
      reviewed_by_user_id = auth.uid(),
      reviewed_at = clock_timestamp(),
      completed_at = clock_timestamp()
  where id = v_request.id
  returning * into v_request;

  perform set_config('horserpg.retirement_transition', 'on', true);
  update public.horses
  set life_stage = 'RETIRED'::public.horse_life_stage
  where id = v_horse.id;
  perform set_config('horserpg.retirement_transition', 'off', true);

  perform public.release_pending_prizes_for_horse(v_horse.id, v_request.id, auth.uid());

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
  ) values (
    auth.uid(), 'GM'::public.app_role, 'HORSE_RETIREMENT_CONFIRMED',
    'horse_retirement_requests', v_request.id::text,
    v_before, public.horse_retirement_request_audit_data(v_request)
  );

  return v_request;
end;
$$;

-- Race Result operations already authenticate as GM.  The shared Horse lock
-- below serializes them against confirm_horse_retirement without a global lock.
create or replace function public.sync_prize_receivable_from_race_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_horse public.horses%rowtype;
  v_before public.prize_receivables%rowtype;
  v_receivable public.prize_receivables%rowtype;
  v_retirement_request_id uuid;
  v_ledger public.prize_receivable_ledger_entries%rowtype;
  v_delta bigint;
begin
  -- This lock is intentionally after the Race Result row operation: Result
  -- corrections/voids serialize on their Result first, then on Horse.  The
  -- retirement path locks its Request then Horse and never takes a Result lock.
  select * into v_horse
  from public.horses
  where id = new.horse_id
  for update;

  if not found then
    raise exception 'Race Result Horse is missing while synchronizing prize receivable'
      using errcode = '23503';
  end if;

  if tg_op = 'INSERT' then
    select owner_id into v_owner_id
    from public.confirmed_race_entries
    where id = new.confirmed_race_entry_id;

    if not found then
      raise exception 'Race Result Confirmed Entry is missing while creating its prize receivable'
        using errcode = '23503';
    end if;

    insert into public.prize_receivables (
      race_result_id, horse_id, owner_id, amount, status,
      created_at, updated_at, released_at, release_retirement_request_id,
      cancelled_at, cancellation_reason
    ) values (
      new.id, new.horse_id, v_owner_id, new.prize_amount,
      case
        when new.status = 'CONFIRMED'::public.race_result_status
          then 'PENDING'::public.prize_receivable_status
        else 'CANCELLED'::public.prize_receivable_status
      end,
      new.recorded_at, new.recorded_at, null, null,
      case when new.status = 'VOIDED'::public.race_result_status then new.voided_at else null end,
      case when new.status = 'VOIDED'::public.race_result_status then new.void_reason else null end
    ) returning * into v_receivable;

    insert into public.audit_logs (
      actor_user_id, actor_role, action, entity_type, entity_id, after_data
    ) values (
      auth.uid(), 'GM'::public.app_role, 'PRIZE_RECEIVABLE_CREATED',
      'prize_receivables', v_receivable.id::text,
      public.prize_receivable_audit_data(v_receivable)
    );

    if new.status = 'CONFIRMED'::public.race_result_status
      and v_horse.life_stage = 'RETIRED'::public.horse_life_stage then
      select id into v_retirement_request_id
      from public.horse_retirement_requests
      where horse_id = v_horse.id
        and status = 'CONFIRMED'::public.horse_retirement_request_status;

      if v_retirement_request_id is null then
        raise exception 'a RETIRED Horse requires one confirmed retirement request before a late Result prize can be released'
          using errcode = '23514';
      end if;

      perform public.release_prize_receivable(
        v_receivable.id,
        v_retirement_request_id,
        auth.uid(),
        'Immediate release for Race Result recorded after Horse retirement'
      );
    end if;

    return new;
  end if;

  if old.status = 'CONFIRMED'::public.race_result_status
    and new.status = 'CONFIRMED'::public.race_result_status
    and old.prize_amount is distinct from new.prize_amount then
    select * into v_before
    from public.prize_receivables
    where race_result_id = new.id
    for update;

    if not found then
      raise exception 'a confirmed Race Result requires one prize receivable before a prize correction'
        using errcode = '23514';
    end if;

    if v_before.status = 'PENDING'::public.prize_receivable_status then
      update public.prize_receivables
      set amount = new.prize_amount
      where id = v_before.id
      returning * into v_receivable;

      insert into public.audit_logs (
        actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data
      ) values (
        auth.uid(), 'GM'::public.app_role, 'PRIZE_RECEIVABLE_ADJUSTED',
        'prize_receivables', v_receivable.id::text,
        public.prize_receivable_audit_data(v_before),
        public.prize_receivable_audit_data(v_receivable)
      );
    elsif v_before.status = 'RELEASED'::public.prize_receivable_status then
      v_delta := new.prize_amount - v_before.amount;

      if v_delta <> 0 then
        select * into v_ledger
        from public.append_prize_receivable_ledger_entry(
          v_before.id,
          v_before.release_retirement_request_id,
          'CORRECTION_ADJUSTMENT'::public.prize_receivable_ledger_entry_kind,
          v_delta,
          auth.uid(),
          'Released prize correction adjustment'
        );

        update public.prize_receivables
        set amount = new.prize_amount
        where id = v_before.id
        returning * into v_receivable;

        insert into public.audit_logs (
          actor_user_id, actor_role, action, entity_type, entity_id, before_data, after_data, reason
        ) values (
          auth.uid(), 'GM'::public.app_role, 'PRIZE_RECEIVABLE_RELEASE_ADJUSTED',
          'prize_receivables', v_receivable.id::text,
          public.prize_receivable_audit_data(v_before),
          jsonb_build_object(
            'receivable', public.prize_receivable_audit_data(v_receivable),
            'amount_delta', v_delta,
            'financial_transaction_id', v_ledger.financial_transaction_id
          ),
          'Released prize correction adjustment'
        );
      end if;
    else
      raise exception 'a cancelled prize receivable cannot be corrected'
        using errcode = '23514';
    end if;

    return new;
  end if;

  if old.status = 'CONFIRMED'::public.race_result_status
    and new.status = 'VOIDED'::public.race_result_status then
    select * into v_before
    from public.prize_receivables
    where race_result_id = new.id
    for update;

    if not found then
      raise exception 'a confirmed Race Result requires one prize receivable before it can be voided'
        using errcode = '23514';
    end if;

    if v_before.status = 'PENDING'::public.prize_receivable_status then
      update public.prize_receivables
      set status = 'CANCELLED'::public.prize_receivable_status,
          cancelled_at = new.voided_at,
          cancellation_reason = new.void_reason
      where id = v_before.id
      returning * into v_receivable;

      insert into public.audit_logs (
        actor_user_id, actor_role, action, entity_type, entity_id,
        before_data, after_data, reason
      ) values (
        auth.uid(), 'GM'::public.app_role, 'PRIZE_RECEIVABLE_CANCELLED',
        'prize_receivables', v_receivable.id::text,
        public.prize_receivable_audit_data(v_before),
        public.prize_receivable_audit_data(v_receivable), new.void_reason
      );
    elsif v_before.status = 'RELEASED'::public.prize_receivable_status then
      select * into v_ledger
      from public.append_prize_receivable_ledger_entry(
        v_before.id,
        v_before.release_retirement_request_id,
        'VOID_REVERSAL'::public.prize_receivable_ledger_entry_kind,
        -v_before.amount,
        auth.uid(),
        new.void_reason
      );

      update public.prize_receivables
      set status = 'CANCELLED'::public.prize_receivable_status,
          cancelled_at = new.voided_at,
          cancellation_reason = new.void_reason
      where id = v_before.id
      returning * into v_receivable;

      insert into public.audit_logs (
        actor_user_id, actor_role, action, entity_type, entity_id,
        before_data, after_data, reason
      ) values (
        auth.uid(), 'GM'::public.app_role, 'PRIZE_RECEIVABLE_RELEASE_REVERSED',
        'prize_receivables', v_receivable.id::text,
        public.prize_receivable_audit_data(v_before),
        jsonb_build_object(
          'receivable', public.prize_receivable_audit_data(v_receivable),
          'amount_delta', -v_before.amount,
          'financial_transaction_id', v_ledger.financial_transaction_id
        ),
        new.void_reason
      );
    else
      raise exception 'a cancelled prize receivable cannot be voided again'
        using errcode = '23514';
    end if;

    return new;
  end if;

  return new;
end;
$$;

alter table public.horse_retirement_requests enable row level security;
alter table public.prize_receivable_ledger_entries enable row level security;

create policy horse_retirement_requests_select_owner_or_gm
on public.horse_retirement_requests
for select to authenticated
using (
  owner_id = public.current_player_owner_id()
  or public.is_current_user_gm()
);

create policy prize_receivable_ledger_entries_select_gm
on public.prize_receivable_ledger_entries
for select to authenticated
using (public.is_current_user_gm());

revoke all on table public.horse_retirement_requests from public, anon, authenticated, service_role;
revoke all on table public.prize_receivable_ledger_entries from public, anon, authenticated, service_role;
grant select on table public.horse_retirement_requests to authenticated;
grant select on table public.prize_receivable_ledger_entries to authenticated;

revoke all on function public.prevent_horse_retirement_request_identity_mutation() from public, anon, authenticated, service_role;
revoke all on function public.enforce_retirement_horse_lifecycle() from public, anon, authenticated, service_role;
revoke all on function public.prevent_prize_receivable_ledger_entry_mutation() from public, anon, authenticated, service_role;
revoke all on function public.prize_receivable_audit_data(public.prize_receivables) from public, anon, authenticated, service_role;
revoke all on function public.horse_retirement_request_audit_data(public.horse_retirement_requests) from public, anon, authenticated, service_role;
revoke all on function public.enforce_prize_receivable_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_prize_receivable_ledger_entry_integrity() from public, anon, authenticated, service_role;
revoke all on function public.enforce_no_pending_prizes_for_retired_horse() from public, anon, authenticated, service_role;
revoke all on function public.append_prize_receivable_ledger_entry(uuid, uuid, public.prize_receivable_ledger_entry_kind, bigint, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.release_prize_receivable(uuid, uuid, uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.release_pending_prizes_for_horse(uuid, uuid, uuid) from public, anon, authenticated, service_role;
revoke all on function public.sync_prize_receivable_from_race_result() from public, anon, authenticated, service_role;
revoke all on function public.submit_horse_retirement_request(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.withdraw_horse_retirement_request(uuid) from public, anon, authenticated, service_role;
revoke all on function public.create_gm_retirement_request(uuid, public.horse_retirement_request_kind, text) from public, anon, authenticated, service_role;
revoke all on function public.reject_horse_retirement_request(uuid, text) from public, anon, authenticated, service_role;
revoke all on function public.confirm_horse_retirement(uuid) from public, anon, authenticated, service_role;

grant execute on function public.submit_horse_retirement_request(uuid, text) to authenticated;
grant execute on function public.withdraw_horse_retirement_request(uuid) to authenticated;
grant execute on function public.create_gm_retirement_request(uuid, public.horse_retirement_request_kind, text) to authenticated;
grant execute on function public.reject_horse_retirement_request(uuid, text) to authenticated;
grant execute on function public.confirm_horse_retirement(uuid) to authenticated;

comment on table public.horse_retirement_requests is
  'Immutable-identity retirement cases. Player requests and GM forced cases enter RETIRE_PENDING; only controlled confirmation retires the Horse and releases pending prizes.';
comment on table public.prize_receivable_ledger_entries is
  'Append-only one-to-one financial linkage for prize release, released-prize correction deltas, and void reversals. The receivable owner, never current Horse ownership, receives each entry.';
comment on function public.confirm_horse_retirement(uuid) is
  'GM-only idempotent retirement confirmation. It locks Request then Horse, rejects future schedules, retires the Horse, and atomically releases every pending prize receivable.';
comment on function public.sync_prize_receivable_from_race_result() is
  'Synchronizes prize receivables with Result facts. Pending amounts update directly; released corrections and voids append matching financial deltas. A Result recorded after retirement releases immediately.';

commit;
