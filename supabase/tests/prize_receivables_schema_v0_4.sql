-- Local SQL verification for HorseRPG v0.4-D Prize Receivables.
-- Run after `npx supabase db reset`. All fixture data is rolled back.

begin;

do $$
declare
  v_function text;
begin
  if not exists (
    select 1 from pg_type where typname = 'prize_receivable_status' and typnamespace = 'public'::regnamespace
  ) or not exists (
    select 1 from pg_tables where schemaname = 'public' and tablename = 'prize_receivables'
  ) then
    raise exception 'Prize Receivables enum or table is missing';
  end if;

  if not (
    select relrowsecurity from pg_class where oid = 'public.prize_receivables'::regclass
  ) then
    raise exception 'prize_receivables does not enable RLS';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.prize_receivables'::regclass
      and contype = 'u'
      and pg_get_constraintdef(oid) like '%race_result_id%'
  ) or not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'prize_receivables_horse_status_idx'
  ) or not exists (
    select 1 from pg_indexes where schemaname = 'public' and indexname = 'prize_receivables_owner_status_idx'
  ) then
    raise exception 'Prize Receivables unique relation or lookup indexes are missing';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.race_results'::regclass
      and tgname = 'race_results_sync_prize_receivable'
      and not tgisinternal
  ) or not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.prize_receivables'::regclass
      and tgname = 'prize_receivables_enforce_integrity'
      and not tgisinternal
  ) then
    raise exception 'Prize Receivables sync or integrity trigger is missing';
  end if;

  v_function := 'public.get_current_owner_prize_receivables()';
  if not exists (
    select 1 from pg_proc as procedure
    where procedure.oid = v_function::regprocedure
      and procedure.prosecdef
      and procedure.proconfig is not null
      and procedure.proconfig::text like '%search_path=%'
  ) or has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
    or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
    or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE')
    or not has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE') then
    raise exception 'PLAYER prize receivables RPC has an incorrect security definition or ACL';
  end if;

  foreach v_function in array array[
    'public.prize_receivable_audit_data(public.prize_receivables)'::text,
    'public.enforce_prize_receivable_integrity()'::text,
    'public.sync_prize_receivable_from_race_result()'::text
  ] loop
    if not exists (
      select 1 from pg_proc as procedure
      where procedure.oid = v_function::regprocedure
        and procedure.prosecdef
        and procedure.proconfig is not null
        and procedure.proconfig::text like '%search_path=%'
    ) or has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE') then
      raise exception 'Prize Receivables helper has an incorrect security definition or client ACL: %', v_function;
    end if;
  end loop;

  if has_table_privilege('public', 'public.prize_receivables', 'SELECT')
    or has_table_privilege('anon', 'public.prize_receivables', 'SELECT')
    or has_table_privilege('service_role', 'public.prize_receivables', 'SELECT')
    or not has_table_privilege('authenticated', 'public.prize_receivables', 'SELECT')
    or has_table_privilege('authenticated', 'public.prize_receivables', 'INSERT')
    or has_table_privilege('authenticated', 'public.prize_receivables', 'UPDATE')
    or has_table_privilege('authenticated', 'public.prize_receivables', 'DELETE') then
    raise exception 'prize_receivables has an incorrect table ACL';
  end if;

  if pg_get_functiondef('public.sync_prize_receivable_from_race_result()'::regprocedure)
    not like '%confirmed_race_entries%' then
    raise exception 'Prize owner is not demonstrably derived from confirmed_race_entries';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f101', 'authenticated', 'authenticated', 'prize-player-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f102', 'authenticated', 'authenticated', 'prize-player-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f103', 'authenticated', 'authenticated', 'prize-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000f104', 'authenticated', 'authenticated', 'prize-unbound@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values
  ('00000000-0000-0000-0000-00000000f201', 'Prize Owner A', 100000000),
  ('00000000-0000-0000-0000-00000000f202', 'Prize Owner B', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000f101', 'PLAYER', '00000000-0000-0000-0000-00000000f201', 'Prize Player A'),
  ('00000000-0000-0000-0000-00000000f102', 'PLAYER', '00000000-0000-0000-0000-00000000f202', 'Prize Player B'),
  ('00000000-0000-0000-0000-00000000f103', 'GM', null, 'Prize GM');

insert into public.game_state (id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id)
values (true, 2037, 6, 3, '00000000-0000-0000-0000-00000000f103');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, owner_id, life_stage
)
values
  ('00000000-0000-0000-0000-00000000f301', 86101, 2034, 'Prize Horse A', 'MALE', 'BAY', 'Prize Sire A', 'Prize Line A', 'Prize Dam A', '00000000-0000-0000-0000-00000000f201', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000f302', 86102, 2034, 'Prize Horse B', 'FEMALE', 'CHESTNUT', 'Prize Sire B', 'Prize Line B', 'Prize Dam B', '00000000-0000-0000-0000-00000000f202', 'ACTIVE');

insert into public.race_catalog (id, name, grade, default_wp_month, default_wp_week, is_active)
values ('00000000-0000-0000-0000-00000000f401', 'Prize Test G2', 'G2', 6, 3, true);

-- Prize Receivables must leave the existing Owner funds RPC completely
-- unchanged: no account, available, or freeze side effect is allowed here.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.prize.funds_a_before', (
  select to_jsonb(funds)::text from public.get_current_owner_funds() as funds
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f102', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('test.prize.funds_b_before', (
  select to_jsonb(funds)::text from public.get_current_owner_funds() as funds
), true);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000f301', 2037, 6::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f401', null, null, null, null
);
select public.create_gm_confirmed_race_entry(
  '00000000-0000-0000-0000-00000000f302', 2037, 6::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f401', null, null, null, null
);
select public.create_actual_race(
  2037, 6::smallint, 3::smallint,
  'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-00000000f401', null
);

select set_config('test.prize.entry_a_id', (
  select id::text from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000f301'
), true);
select set_config('test.prize.entry_b_id', (
  select id::text from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000f302'
), true);
select set_config('test.prize.actual_race_id', (
  select id::text from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000f401'
), true);
select set_config('test.prize.financial_count_before', (select count(*)::text from public.financial_transactions), true);

-- 50 million and zero-prize Results both generate exactly one PENDING row.
select public.record_race_result(
  current_setting('test.prize.entry_a_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  1::smallint, 50000000::bigint, 'Prize Jockey A', null, null
);
select public.record_race_result(
  current_setting('test.prize.entry_b_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  2::smallint, 0::bigint, null, null, null
);
select set_config('test.prize.result_a_id', (
  select id::text from public.race_results where confirmed_race_entry_id = current_setting('test.prize.entry_a_id', true)::uuid and status = 'CONFIRMED'::public.race_result_status
), true);
select set_config('test.prize.result_b_id', (
  select id::text from public.race_results where confirmed_race_entry_id = current_setting('test.prize.entry_b_id', true)::uuid and status = 'CONFIRMED'::public.race_result_status
), true);
select set_config('test.prize.receivable_a_id', (
  select id::text from public.prize_receivables where race_result_id = current_setting('test.prize.result_a_id', true)::uuid
), true);
select set_config('test.prize.receivable_b_id', (
  select id::text from public.prize_receivables where race_result_id = current_setting('test.prize.result_b_id', true)::uuid
), true);

do $$
begin
  if not exists (
    select 1
    from public.prize_receivables
    where id = current_setting('test.prize.receivable_a_id', true)::uuid
      and horse_id = '00000000-0000-0000-0000-00000000f301'
      and owner_id = '00000000-0000-0000-0000-00000000f201'
      and amount = 50000000
      and status = 'PENDING'::public.prize_receivable_status
  ) or not exists (
    select 1
    from public.prize_receivables
    where id = current_setting('test.prize.receivable_b_id', true)::uuid
      and horse_id = '00000000-0000-0000-0000-00000000f302'
      and owner_id = '00000000-0000-0000-0000-00000000f202'
      and amount = 0
      and status = 'PENDING'::public.prize_receivable_status
  ) then
    raise exception 'recording a result did not atomically create the correct pending prize receivable';
  end if;
end;
$$;

-- Exact Record retry has no Result, Prize Receivable, or Audit duplication.
select public.record_race_result(
  current_setting('test.prize.entry_a_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  1::smallint, 50000000::bigint, 'Prize Jockey A', null, null
);

do $$
begin
  if (select count(*) from public.prize_receivables where race_result_id = current_setting('test.prize.result_a_id', true)::uuid) <> 1
    or (select count(*) from public.audit_logs
        where action = 'PRIZE_RECEIVABLE_CREATED'
          and after_data ->> 'race_result_id' = current_setting('test.prize.result_a_id', true)) <> 1 then
    raise exception 'idempotent race-result record duplicated a prize receivable or creation audit';
  end if;
end;
$$;

-- Prize correction changes the existing row; zero to positive and back follows
-- the same one-to-one relation.
select public.correct_race_result(
  current_setting('test.prize.result_a_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  1::smallint, 30000000::bigint, 'Prize Jockey A', null, null, 'correct prize A'
);
select public.correct_race_result(
  current_setting('test.prize.result_b_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  2::smallint, 10000000::bigint, null, null, null, 'zero to positive'
);
select public.correct_race_result(
  current_setting('test.prize.result_b_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  2::smallint, 0::bigint, null, null, null, 'positive to zero'
);

do $$
begin
  if not exists (
    select 1 from public.prize_receivables
    where id = current_setting('test.prize.receivable_a_id', true)::uuid
      and amount = 30000000 and status = 'PENDING'::public.prize_receivable_status
  ) or not exists (
    select 1 from public.prize_receivables
    where id = current_setting('test.prize.receivable_b_id', true)::uuid
      and amount = 0 and status = 'PENDING'::public.prize_receivable_status
  ) or (select count(*) from public.audit_logs
      where action = 'PRIZE_RECEIVABLE_ADJUSTED'
        and entity_id = current_setting('test.prize.receivable_a_id', true)) <> 1
    or (select count(*) from public.audit_logs
      where action = 'PRIZE_RECEIVABLE_ADJUSTED'
        and entity_id = current_setting('test.prize.receivable_b_id', true)) <> 2 then
    raise exception 'prize correction did not adjust the existing receivable and audit exactly once per actual amount change';
  end if;
end;
$$;

-- A correction without an amount change must not create a prize adjustment.
select public.correct_race_result(
  current_setting('test.prize.result_a_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  3::smallint, 30000000::bigint, 'Prize Jockey A Corrected', 'LATE', 'non-prize correction', 'correct non-prize facts'
);

do $$
begin
  if (select count(*) from public.audit_logs
      where action = 'PRIZE_RECEIVABLE_ADJUSTED'
        and entity_id = current_setting('test.prize.receivable_a_id', true)) <> 1 then
    raise exception 'non-prize race-result correction wrote an unnecessary prize adjustment audit';
  end if;
end;
$$;

-- Void cancels, remains idempotent, and re-record creates a distinct pending
-- receivable while preserving the cancelled historical source row.
select public.void_race_result(
  current_setting('test.prize.result_a_id', true)::uuid, 'void prize result A'
);
select public.void_race_result(
  current_setting('test.prize.result_a_id', true)::uuid, 'void prize result A'
);

do $$
begin
  if not exists (
    select 1 from public.prize_receivables
    where id = current_setting('test.prize.receivable_a_id', true)::uuid
      and amount = 30000000
      and status = 'CANCELLED'::public.prize_receivable_status
      and cancelled_at is not null
      and cancellation_reason = 'void prize result A'
  ) or (select count(*) from public.audit_logs
      where action = 'PRIZE_RECEIVABLE_CANCELLED'
        and entity_id = current_setting('test.prize.receivable_a_id', true)) <> 1 then
    raise exception 'void did not cancel the prize receivable exactly once';
  end if;
end;
$$;

select public.record_race_result(
  current_setting('test.prize.entry_a_id', true)::uuid,
  current_setting('test.prize.actual_race_id', true)::uuid,
  1::smallint, 3000000::bigint, null, null, 're-record after void'
);
select set_config('test.prize.re_recorded_result_a_id', (
  select id::text from public.race_results
  where confirmed_race_entry_id = current_setting('test.prize.entry_a_id', true)::uuid
    and status = 'CONFIRMED'::public.race_result_status
), true);
select set_config('test.prize.re_recorded_receivable_a_id', (
  select id::text from public.prize_receivables
  where race_result_id = current_setting('test.prize.re_recorded_result_a_id', true)::uuid
), true);

do $$
begin
  if current_setting('test.prize.re_recorded_result_a_id', true)::uuid = current_setting('test.prize.result_a_id', true)::uuid
    or current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid = current_setting('test.prize.receivable_a_id', true)::uuid
    or (select count(*) from public.prize_receivables
        where race_result_id in (
          current_setting('test.prize.result_a_id', true)::uuid,
          current_setting('test.prize.re_recorded_result_a_id', true)::uuid
        )) <> 2
    or not exists (
      select 1 from public.prize_receivables
      where id = current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid
        and amount = 3000000 and status = 'PENDING'::public.prize_receivable_status
    ) then
    raise exception 're-record after void did not retain cancelled history and create one new pending receivable';
  end if;
end;
$$;

-- Integrity guards prevent a receivable being reassigned or status-diverged,
-- even if a future privileged server path accidentally writes the base table.
reset role;
do $$
begin
  begin
    update public.prize_receivables
    set owner_id = '00000000-0000-0000-0000-00000000f202'
    where id = current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid;
    raise exception 'prize receivable identity was mutable' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    update public.prize_receivables
    set status = 'CANCELLED'::public.prize_receivable_status,
        cancelled_at = now(), cancellation_reason = 'manual divergence'
    where id = current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid;
    raise exception 'prize receivable status diverged from confirmed Race Result' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;

-- Dedicated transactional backfill verification: temporarily remove two
-- derived rows, run the same insert-select rule as the migration, and confirm
-- CONFIRMED and VOIDED historical Result rows reconstruct PENDING/CANCELLED
-- rows without creating a financial side effect.
delete from public.prize_receivables
where race_result_id in (
  current_setting('test.prize.result_a_id', true)::uuid,
  current_setting('test.prize.result_b_id', true)::uuid
);

insert into public.prize_receivables (
  race_result_id, horse_id, owner_id, amount, status,
  created_at, updated_at, cancelled_at, cancellation_reason
)
select
  result.id,
  result.horse_id,
  entry.owner_id,
  result.prize_amount,
  case when result.status = 'CONFIRMED'::public.race_result_status
    then 'PENDING'::public.prize_receivable_status
    else 'CANCELLED'::public.prize_receivable_status
  end,
  result.recorded_at,
  result.recorded_at,
  case when result.status = 'VOIDED'::public.race_result_status then result.voided_at else null end,
  case when result.status = 'VOIDED'::public.race_result_status then result.void_reason else null end
from public.race_results as result
join public.confirmed_race_entries as entry on entry.id = result.confirmed_race_entry_id
where result.id in (
  current_setting('test.prize.result_a_id', true)::uuid,
  current_setting('test.prize.result_b_id', true)::uuid
)
on conflict (race_result_id) do nothing;

do $$
begin
  if not exists (
    select 1 from public.prize_receivables
    where race_result_id = current_setting('test.prize.result_a_id', true)::uuid
      and amount = 30000000
      and status = 'CANCELLED'::public.prize_receivable_status
      and cancellation_reason = 'void prize result A'
  ) or not exists (
    select 1 from public.prize_receivables
    where race_result_id = current_setting('test.prize.result_b_id', true)::uuid
      and amount = 0 and status = 'PENDING'::public.prize_receivable_status
  ) then
    raise exception 'backfill reconstruction did not preserve confirmed/voided prize receivable facts';
  end if;
end;
$$;

select set_config('test.prize.receivable_a_id', (
  select id::text from public.prize_receivables
  where race_result_id = current_setting('test.prize.result_a_id', true)::uuid
), true);
select set_config('test.prize.receivable_b_id', (
  select id::text from public.prize_receivables
  where race_result_id = current_setting('test.prize.result_b_id', true)::uuid
), true);

-- GM sees base history but cannot write it directly; players only get their
-- own pending rows through the no-argument SECURITY DEFINER RPC.
do $$
begin
  if (select count(*) from public.prize_receivables) <> (select count(*) from public.race_results) then
    raise exception 'Race Result to Prize Receivable relation is not one-to-one';
  end if;

  begin
    insert into public.prize_receivables (
      race_result_id, horse_id, owner_id, amount, status
    ) values (
      current_setting('test.prize.re_recorded_result_a_id', true)::uuid,
      '00000000-0000-0000-0000-00000000f301',
      '00000000-0000-0000-0000-00000000f201',
      3000000,
      'PENDING'::public.prize_receivable_status
    );
    raise exception 'duplicate Race Result prize receivable was accepted' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f101', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if (select count(*) from public.prize_receivables) <> 0 then
    raise exception 'PLAYER read the GM-only prize_receivables base table';
  end if;

  if not exists (
    select 1 from public.get_current_owner_prize_receivables()
    where prize_receivable_id = current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid
      and race_result_id = current_setting('test.prize.re_recorded_result_a_id', true)::uuid
      and horse_id = '00000000-0000-0000-0000-00000000f301'
      and amount = 3000000
  ) or exists (
    select 1 from public.get_current_owner_prize_receivables()
    where horse_id = '00000000-0000-0000-0000-00000000f302'
  ) or exists (
    select 1 from public.get_current_owner_prize_receivables()
    where prize_receivable_id = current_setting('test.prize.receivable_a_id', true)::uuid
  ) then
    raise exception 'PLAYER A prize RPC leaked another Owner or cancelled history';
  end if;

  begin
    insert into public.prize_receivables (
      race_result_id, horse_id, owner_id, amount, status
    ) values (
      current_setting('test.prize.re_recorded_result_a_id', true)::uuid,
      '00000000-0000-0000-0000-00000000f301',
      '00000000-0000-0000-0000-00000000f201',
      3000000,
      'PENDING'::public.prize_receivable_status
    );
    raise exception 'PLAYER wrote prize_receivables directly' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  if (select to_jsonb(funds)::text from public.get_current_owner_funds() as funds)
    <> current_setting('test.prize.funds_a_before', true) then
    raise exception 'Prize Receivables changed PLAYER A account, available, or frozen funds';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f102', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if not exists (
    select 1 from public.get_current_owner_prize_receivables()
    where prize_receivable_id = current_setting('test.prize.receivable_b_id', true)::uuid
      and horse_id = '00000000-0000-0000-0000-00000000f302'
      and amount = 0
  ) or exists (
    select 1 from public.get_current_owner_prize_receivables()
    where horse_id = '00000000-0000-0000-0000-00000000f301'
  ) then
    raise exception 'PLAYER B prize RPC did not isolate Owner rows';
  end if;

  if (select to_jsonb(funds)::text from public.get_current_owner_funds() as funds)
    <> current_setting('test.prize.funds_b_before', true) then
    raise exception 'Prize Receivables changed PLAYER B account, available, or frozen funds';
  end if;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if (select count(*) from public.prize_receivables) <> (select count(*) from public.race_results) then
    raise exception 'GM could not read complete prize receivable history under RLS';
  end if;

  begin
    perform public.get_current_owner_prize_receivables();
    raise exception 'GM called PLAYER-only prize receivables RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.prize_receivables
    set amount = 1
    where id = current_setting('test.prize.re_recorded_receivable_a_id', true)::uuid;
    raise exception 'GM directly updated a prize receivable' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f104', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.get_current_owner_prize_receivables();
    raise exception 'unbound authenticated user called PLAYER-only prize receivables RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role anon;
do $$
begin
  begin
    perform public.get_current_owner_prize_receivables();
    raise exception 'anon called PLAYER-only prize receivables RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role service_role;
do $$
begin
  begin
    perform public.get_current_owner_prize_receivables();
    raise exception 'service_role called PLAYER-only prize receivables RPC despite ACL' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
do $$
begin
  if (select count(*) from public.financial_transactions) <> current_setting('test.prize.financial_count_before', true)::integer then
    raise exception 'Prize Receivable record, correction, void, re-record, or backfill changed the financial ledger';
  end if;

  if exists (
    select 1
    from public.audit_logs
    where action in ('PRIZE_RECEIVABLE_CREATED', 'PRIZE_RECEIVABLE_ADJUSTED', 'PRIZE_RECEIVABLE_CANCELLED')
      and actor_role <> 'GM'::public.app_role
  ) then
    raise exception 'Prize Receivable operational audit did not retain its GM actor role';
  end if;
end;
$$;

rollback;
