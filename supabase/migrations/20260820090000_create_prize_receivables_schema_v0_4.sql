-- HorseRPG v0.4-D Prize Receivables database layer.
-- A prize receivable is a pending accounting fact derived atomically from a
-- Race Result. It is deliberately not an account balance, ledger entry, or
-- source of available bidding funds.

begin;

create type public.prize_receivable_status as enum ('PENDING', 'CANCELLED');

create table public.prize_receivables (
  id uuid primary key default gen_random_uuid(),
  race_result_id uuid not null unique references public.race_results(id) on delete restrict,
  horse_id uuid not null references public.horses(id) on delete restrict,
  owner_id uuid not null references public.owners(id) on delete restrict,
  amount bigint not null check (amount >= 0),
  status public.prize_receivable_status not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now(),
  cancelled_at timestamptz,
  cancellation_reason text,
  constraint prize_receivables_cancellation_state_check check (
    (
      status = 'PENDING'::public.prize_receivable_status
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
  )
);

create index prize_receivables_horse_status_idx
  on public.prize_receivables (horse_id, status);

create index prize_receivables_owner_status_idx
  on public.prize_receivables (owner_id, status);

-- Safe for existing deployments: every historical Race Result gets exactly
-- one receivable. This runs before the operational sync trigger, so no row is
-- duplicated and migration backfill intentionally creates no fake GM audit.
insert into public.prize_receivables (
  race_result_id,
  horse_id,
  owner_id,
  amount,
  status,
  created_at,
  updated_at,
  cancelled_at,
  cancellation_reason
)
select
  result.id,
  result.horse_id,
  entry.owner_id,
  result.prize_amount,
  case
    when result.status = 'CONFIRMED'::public.race_result_status
      then 'PENDING'::public.prize_receivable_status
    else 'CANCELLED'::public.prize_receivable_status
  end,
  result.recorded_at,
  result.recorded_at,
  case
    when result.status = 'VOIDED'::public.race_result_status then result.voided_at
    else null
  end,
  case
    when result.status = 'VOIDED'::public.race_result_status then result.void_reason
    else null
  end
from public.race_results as result
join public.confirmed_race_entries as entry
  on entry.id = result.confirmed_race_entry_id
on conflict (race_result_id) do nothing;

do $$
begin
  if (select count(*) from public.race_results)
    <> (select count(*) from public.prize_receivables) then
    raise exception 'Prize Receivables backfill must create exactly one row for every Race Result'
      using errcode = '23514';
  end if;
end;
$$;

create function public.prize_receivable_audit_data(
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
    'cancelled_at', p_prize_receivable.cancelled_at,
    'cancellation_reason', p_prize_receivable.cancellation_reason
  );
$$;

-- This makes the source relation a database invariant. In particular, Owner
-- comes from the immutable Confirmed Entry owner snapshot, never from the
-- Horse's current owner.
create function public.enforce_prize_receivable_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result public.race_results%rowtype;
  v_entry_owner_id uuid;
  v_expected_status public.prize_receivable_status;
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
    raise exception 'a cancelled prize receivable cannot return to pending'
      using errcode = '23514';
  end if;

  select *
  into v_result
  from public.race_results
  where id = new.race_result_id
  for key share;

  if not found then
    raise exception 'a prize receivable requires an existing Race Result'
      using errcode = '23503';
  end if;

  select owner_id
  into v_entry_owner_id
  from public.confirmed_race_entries
  where id = v_result.confirmed_race_entry_id
  for key share;

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

  v_expected_status := case
    when v_result.status = 'CONFIRMED'::public.race_result_status
      then 'PENDING'::public.prize_receivable_status
    else 'CANCELLED'::public.prize_receivable_status
  end;

  if new.status <> v_expected_status then
    raise exception 'a prize receivable status must match its Race Result status'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger prize_receivables_enforce_integrity
before insert or update on public.prize_receivables
for each row execute function public.enforce_prize_receivable_integrity();

create trigger prize_receivables_set_updated_at
before update on public.prize_receivables
for each row execute function public.set_updated_at();

-- Operational writes occur only from the Race Result transaction. If this
-- trigger cannot synchronize its one-to-one receivable or audit, PostgreSQL
-- rolls back the originating Record, Correction, or Void operation too.
create function public.sync_prize_receivable_from_race_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_before public.prize_receivables%rowtype;
  v_receivable public.prize_receivables%rowtype;
begin
  if tg_op = 'INSERT' then
    select owner_id
    into v_owner_id
    from public.confirmed_race_entries
    where id = new.confirmed_race_entry_id
    for key share;

    if not found then
      raise exception 'Race Result Confirmed Entry is missing while creating its prize receivable'
        using errcode = '23503';
    end if;

    insert into public.prize_receivables (
      race_result_id,
      horse_id,
      owner_id,
      amount,
      status,
      created_at,
      updated_at,
      cancelled_at,
      cancellation_reason
    ) values (
      new.id,
      new.horse_id,
      v_owner_id,
      new.prize_amount,
      case
        when new.status = 'CONFIRMED'::public.race_result_status
          then 'PENDING'::public.prize_receivable_status
        else 'CANCELLED'::public.prize_receivable_status
      end,
      new.recorded_at,
      new.recorded_at,
      case when new.status = 'VOIDED'::public.race_result_status then new.voided_at else null end,
      case when new.status = 'VOIDED'::public.race_result_status then new.void_reason else null end
    )
    on conflict (race_result_id) do nothing
    returning * into v_receivable;

    if found then
      insert into public.audit_logs (
        actor_user_id, actor_role, action, entity_type, entity_id, after_data
      ) values (
        auth.uid(),
        'GM'::public.app_role,
        'PRIZE_RECEIVABLE_CREATED',
        'prize_receivables',
        v_receivable.id::text,
        public.prize_receivable_audit_data(v_receivable)
      );
    end if;

    return new;
  end if;

  if old.status = 'CONFIRMED'::public.race_result_status
    and new.status = 'CONFIRMED'::public.race_result_status
    and old.prize_amount is distinct from new.prize_amount then
    select *
    into v_before
    from public.prize_receivables
    where race_result_id = new.id
    for update;

    if not found or v_before.status <> 'PENDING'::public.prize_receivable_status then
      raise exception 'a confirmed Race Result requires one pending prize receivable before a prize correction'
        using errcode = '23514';
    end if;

    update public.prize_receivables
    set amount = new.prize_amount
    where id = v_before.id
    returning * into v_receivable;

    insert into public.audit_logs (
      actor_user_id, actor_role, action, entity_type, entity_id,
      before_data, after_data
    ) values (
      auth.uid(),
      'GM'::public.app_role,
      'PRIZE_RECEIVABLE_ADJUSTED',
      'prize_receivables',
      v_receivable.id::text,
      public.prize_receivable_audit_data(v_before),
      public.prize_receivable_audit_data(v_receivable)
    );

    return new;
  end if;

  if old.status = 'CONFIRMED'::public.race_result_status
    and new.status = 'VOIDED'::public.race_result_status then
    select *
    into v_before
    from public.prize_receivables
    where race_result_id = new.id
    for update;

    if not found or v_before.status <> 'PENDING'::public.prize_receivable_status then
      raise exception 'a confirmed Race Result requires one pending prize receivable before it can be voided'
        using errcode = '23514';
    end if;

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
      auth.uid(),
      'GM'::public.app_role,
      'PRIZE_RECEIVABLE_CANCELLED',
      'prize_receivables',
      v_receivable.id::text,
      public.prize_receivable_audit_data(v_before),
      public.prize_receivable_audit_data(v_receivable),
      new.void_reason
    );

    return new;
  end if;

  return new;
end;
$$;

create trigger race_results_sync_prize_receivable
after insert or update of prize_amount, status on public.race_results
for each row execute function public.sync_prize_receivable_from_race_result();

alter table public.prize_receivables enable row level security;

create policy prize_receivables_select_gm
on public.prize_receivables
for select to authenticated
using (public.is_current_user_gm());

-- This RPC intentionally returns only the calling PLAYER's pending facts. It
-- takes no scope parameter, so callers cannot request another Owner's rows.
create function public.get_current_owner_prize_receivables()
returns table (
  prize_receivable_id uuid,
  race_result_id uuid,
  horse_id uuid,
  amount bigint,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if auth.uid() is null then
    raise exception 'an authenticated PLAYER is required to read pending prize receivables'
      using errcode = '42501';
  end if;

  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null;

  if v_owner_id is null then
    raise exception 'only a PLAYER with a valid Owner binding may read pending prize receivables'
      using errcode = '42501';
  end if;

  return query
  select
    receivable.id,
    receivable.race_result_id,
    receivable.horse_id,
    receivable.amount,
    receivable.created_at,
    receivable.updated_at
  from public.prize_receivables as receivable
  where receivable.owner_id = v_owner_id
    and receivable.status = 'PENDING'::public.prize_receivable_status
  order by receivable.created_at desc, receivable.id;
end;
$$;

revoke all on table public.prize_receivables from public, anon, authenticated, service_role;
grant select on table public.prize_receivables to authenticated;

revoke all on function public.prize_receivable_audit_data(public.prize_receivables) from public, anon, authenticated, service_role;
revoke all on function public.enforce_prize_receivable_integrity() from public, anon, authenticated, service_role;
revoke all on function public.sync_prize_receivable_from_race_result() from public, anon, authenticated, service_role;
revoke all on function public.get_current_owner_prize_receivables() from public, anon, authenticated, service_role;
grant execute on function public.get_current_owner_prize_receivables() to authenticated;

comment on table public.prize_receivables is
  'One immutable-identity pending/cancelled prize receivable per Race Result. It is not a ledger entry or available Owner funds; future release must pay prize_receivables.owner_id, not horses.owner_id.';
comment on table public.race_results is
  'GM-recorded Horse post-race facts. prize_amount is a Winning Post result fact; its matching Prize Receivable is synchronized atomically in v0.4-D, without a financial transaction or available-funds side effect.';
comment on function public.get_current_owner_prize_receivables() is
  'PLAYER-only pending prize projection for the current auth.uid() Owner; no owner_id argument and no cancelled history.';

commit;
