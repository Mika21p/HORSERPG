-- Local structural and ACL verification for v0.3-A public-auction Realtime.
-- Run after `npx supabase db reset`. Fixtures are rolled back.

begin;

do $$
declare
  v_receive_policy text;
  v_snapshot_definition text;
begin
  foreach v_receive_policy in array array[
    'public.broadcast_public_auction_event_change()'::text,
    'public.broadcast_public_auction_lot_change()'::text,
    'public.broadcast_public_auction_round_change()'::text,
    'public.broadcast_public_auction_bid_insert()'::text
  ] loop
    if not exists (
      select 1 from pg_proc as procedure where procedure.oid = v_receive_policy::regprocedure
    ) then
      raise exception 'missing public-auction Realtime trigger function: %', v_receive_policy;
    end if;

    if has_function_privilege('public', v_receive_policy::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_receive_policy::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_receive_policy::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_receive_policy::regprocedure, 'EXECUTE') then
      raise exception 'public-auction Realtime trigger function has a client EXECUTE ACL: %', v_receive_policy;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_proc as procedure
    where procedure.oid = 'public.get_public_auction_snapshot(uuid)'::regprocedure
      and not procedure.prosecdef
      and procedure.proconfig is not null
      and procedure.proconfig::text like '%search_path%'
  ) then
    raise exception 'atomic public-auction Snapshot RPC is missing, not SECURITY INVOKER, or has no fixed search_path';
  end if;

  if has_function_privilege('public', 'public.get_public_auction_snapshot(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', 'public.get_public_auction_snapshot(uuid)'::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', 'public.get_public_auction_snapshot(uuid)'::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.get_public_auction_snapshot(uuid)'::regprocedure, 'EXECUTE') then
    raise exception 'atomic public-auction Snapshot RPC has an incorrect EXECUTE ACL';
  end if;

  select pg_get_functiondef('public.get_public_auction_snapshot(uuid)'::regprocedure)
  into v_snapshot_definition;

  if v_snapshot_definition ~ 'public\\.public_auction_rollback_requests'
    or v_snapshot_definition ~ 'public\\.financial_transactions'
    or v_snapshot_definition ~ 'public\\.audit_logs'
    or v_snapshot_definition ~ 'public\\.public_auction_settlements' then
    raise exception 'atomic public-auction Snapshot RPC directly references internal data';
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and policyname = 'public_auction_realtime_receive_authenticated'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%realtime.topic()%'
      and qual like '%public-auction:%%'
  ) then
    raise exception 'public-auction Realtime receive policy is missing or not topic-scoped';
  end if;

  -- Supabase manages the relation ACL for its internal Realtime owner. The
  -- application security boundary is the policy set: exactly one scoped
  -- authenticated SELECT policy and no client INSERT policy.
  if exists (
    select 1
    from pg_policies
    where schemaname = 'realtime'
      and tablename = 'messages'
      and cmd in ('INSERT', 'ALL')
      and (
        'authenticated'::name = any(roles)
        or 'anon'::name = any(roles)
        or 'public'::name = any(roles)
      )
  ) then
    raise exception 'a client Realtime INSERT policy unexpectedly exists';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.public_auction_events'::regclass
      and tgname = 'public_auction_events_broadcast_realtime_change'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.public_auction_lots'::regclass
      and tgname = 'public_auction_lots_broadcast_realtime_change'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.public_auction_rounds'::regclass
      and tgname = 'public_auction_rounds_broadcast_realtime_change'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.public_auction_bids'::regclass
      and tgname = 'public_auction_bids_broadcast_realtime_insert'
      and not tgisinternal
  ) then
    raise exception 'one or more public-auction Realtime triggers are missing';
  end if;

  if exists (
    select 1
    from unnest(array[
      'public.broadcast_public_auction_event_change()'::regprocedure,
      'public.broadcast_public_auction_lot_change()'::regprocedure,
      'public.broadcast_public_auction_round_change()'::regprocedure,
      'public.broadcast_public_auction_bid_insert()'::regprocedure
    ]) as trigger_function
    where pg_get_functiondef(trigger_function) not like '%realtime.send%'
      or pg_get_functiondef(trigger_function) not like '%exception when others%'
      or pg_get_functiondef(trigger_function) not like '%public auction realtime notification failed [%]%'
  ) then
    raise exception 'a public-auction Broadcast trigger does not isolate Realtime send failures';
  end if;
end;
$$;

set local role authenticated;
do $$
begin
  perform public.get_public_auction_snapshot('00000000-0000-0000-0000-000000009001'::uuid);
end;
$$;
reset role;

set local role anon;
do $$
begin
  begin
    perform public.get_public_auction_snapshot('00000000-0000-0000-0000-000000009001'::uuid);
    raise exception 'anon called the atomic public-auction Snapshot RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

-- Realtime.topic() is the exact helper used during a private-channel join.
set local role authenticated;
select set_config('realtime.topic', 'public-auction:00000000-0000-0000-0000-000000009001', true);
do $$
begin
  if realtime.topic() <> 'public-auction:00000000-0000-0000-0000-000000009001' then
    raise exception 'Realtime topic helper did not preserve the requested public-auction topic';
  end if;

  begin
    insert into realtime.messages (topic, extension, payload, event, private)
    values ('public-auction:00000000-0000-0000-0000-000000009001', 'broadcast', '{}'::jsonb, 'client_write', true);
    raise exception 'authenticated client inserted a Realtime broadcast' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

set local role anon;
do $$
begin
  begin
    insert into realtime.messages (topic, extension, payload, event, private)
    values ('public-auction:00000000-0000-0000-0000-000000009001', 'broadcast', '{}'::jsonb, 'client_write', true);
    raise exception 'anon inserted a Realtime broadcast' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

rollback;
