-- Local-only verification for GM manual Owner funds adjustments.
-- Run after all migrations. This transaction always rolls back.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000008002', 'authenticated', 'authenticated', 'funds-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000008003', 'authenticated', 'authenticated', 'funds-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000008001', 'Funds Test Owner', 50000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000008002', 'GM', null, 'Funds GM'),
  ('00000000-0000-0000-0000-000000008003', 'PLAYER', '00000000-0000-0000-0000-000000008001', 'Funds Player');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, life_stage
) values
  ('00000000-0000-0000-0000-000000008011', 80011, 2030, 'Secret Freeze Foal', 'MALE', 'Bay', 'Sire A', 'Line A', 'BMS A', 'FOAL'),
  ('00000000-0000-0000-0000-000000008012', 80012, 2031, 'Auction Freeze Foal', 'FEMALE', 'Chestnut', 'Sire B', 'Line B', 'BMS B', 'FOAL');

insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values
  ('00000000-0000-0000-0000-000000008021', 2030, now() - interval '1 day', now() + interval '1 day', 'OPEN'),
  ('00000000-0000-0000-0000-000000008022', 2031, now() - interval '2 days', now() - interval '1 day', 'SETTLED');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
  ('00000000-0000-0000-0000-000000008031', '00000000-0000-0000-0000-000000008021', '00000000-0000-0000-0000-000000008011', 0, 'LISTED'),
  ('00000000-0000-0000-0000-000000008032', '00000000-0000-0000-0000-000000008022', '00000000-0000-0000-0000-000000008012', 0, 'UNSOLD');

insert into public.foal_trade_settlements (id, lot_id, session_id, horse_id, status)
values (
  '00000000-0000-0000-0000-000000008041',
  '00000000-0000-0000-0000-000000008032',
  '00000000-0000-0000-0000-000000008022',
  '00000000-0000-0000-0000-000000008012',
  'UNSOLD'
);

insert into public.public_auction_events (id, wp_year, name, status, minimum_increment)
values ('00000000-0000-0000-0000-000000008051', 2031, 'Funds Test Auction', 'OPEN', 100000);

insert into public.public_auction_lots (
  id, event_id, horse_id, lot_number, starting_price, evaluation_value
) values (
  '00000000-0000-0000-0000-000000008061',
  '00000000-0000-0000-0000-000000008051',
  '00000000-0000-0000-0000-000000008012',
  1,
  100000,
  0
);

insert into public.public_auction_rounds (
  id, lot_id, round_number, status, current_price, current_winner_owner_id, close_at
) values (
  '00000000-0000-0000-0000-000000008071',
  '00000000-0000-0000-0000-000000008061',
  1,
  'BIDDING',
  10000000,
  '00000000-0000-0000-0000-000000008001',
  now() + interval '10 seconds'
);

update public.public_auction_lots
set current_round_id = '00000000-0000-0000-0000-000000008071'
where id = '00000000-0000-0000-0000-000000008061';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.submit_foal_trade_secret_bid(
  '00000000-0000-0000-0000-000000008031',
  20000000
);

do $$
begin
  begin
    perform public.get_gm_owner_financial_summary('00000000-0000-0000-0000-000000008001');
    raise exception 'PLAYER read a GM Owner financial summary';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.adjust_owner_funds(
      '00000000-0000-0000-0000-000000008001',
      1,
      'PLAYER attempt',
      '00000000-0000-0000-0000-000000008091'
    );
    raise exception 'PLAYER adjusted Owner funds';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.financial_transactions (owner_id, amount, transaction_kind)
    values ('00000000-0000-0000-0000-000000008001', 1, 'PLAYER_DIRECT_WRITE');
    raise exception 'PLAYER directly inserted a financial transaction';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_summary record;
  v_first public.financial_transactions%rowtype;
  v_retry public.financial_transactions%rowtype;
  v_transaction_count integer;
  v_audit_count integer;
begin
  select * into v_summary
  from public.get_gm_owner_financial_summary('00000000-0000-0000-0000-000000008001');

  if (v_summary.account_funds, v_summary.foal_trade_frozen_funds,
      v_summary.public_auction_frozen_funds, v_summary.total_frozen_funds,
      v_summary.available_funds)
    is distinct from (50000000::bigint, 20000000::bigint, 10000000::bigint, 30000000::bigint, 20000000::bigint) then
    raise exception 'unexpected initial GM funds summary';
  end if;

  select * into v_first
  from public.adjust_owner_funds(
    '00000000-0000-0000-0000-000000008001',
    -20000000,
    'Correct initial playtest allocation',
    '00000000-0000-0000-0000-000000008101'
  );

  select * into v_retry
  from public.adjust_owner_funds(
    '00000000-0000-0000-0000-000000008001',
    -20000000,
    'Correct initial playtest allocation',
    '00000000-0000-0000-0000-000000008101'
  );

  if v_first.id <> v_retry.id then
    raise exception 'same manual adjustment request did not return the existing transaction';
  end if;

  select count(*) into v_transaction_count
  from public.financial_transactions
  where source_entity_type = 'GM_OWNER_FUNDS_ADJUSTMENT'
    and source_entity_id = '00000000-0000-0000-0000-000000008101';

  select count(*) into v_audit_count
  from public.audit_logs
  where action = 'OWNER_FUNDS_MANUAL_ADJUSTED'
    and request_id = '00000000-0000-0000-0000-000000008101';

  if v_transaction_count <> 1 or v_audit_count <> 1 then
    raise exception 'manual adjustment retry created duplicate ledger or audit facts';
  end if;

  select * into v_summary
  from public.get_gm_owner_financial_summary('00000000-0000-0000-0000-000000008001');

  if (v_summary.account_funds, v_summary.available_funds)
    is distinct from (30000000::bigint, 0::bigint) then
    raise exception 'manual debit did not preserve the expected frozen-funds position';
  end if;

  begin
    perform public.adjust_owner_funds(
      '00000000-0000-0000-0000-000000008001',
      -1,
      'Would violate available funds',
      '00000000-0000-0000-0000-000000008102'
    );
    raise exception 'manual adjustment created a negative available balance';
  exception when check_violation then null;
  end;

  begin
    perform public.adjust_owner_funds(
      '00000000-0000-0000-0000-000000008001',
      -19999999,
      'Conflicting retry facts',
      '00000000-0000-0000-0000-000000008101'
    );
    raise exception 'conflicting manual-adjustment retry was accepted';
  exception when check_violation then null;
  end;

  perform public.adjust_owner_funds(
    '00000000-0000-0000-0000-000000008001',
    5000000,
    'GM goodwill credit',
    '00000000-0000-0000-0000-000000008103'
  );

  select * into v_summary
  from public.get_gm_owner_financial_summary('00000000-0000-0000-0000-000000008001');

  if (v_summary.account_funds, v_summary.foal_trade_frozen_funds,
      v_summary.public_auction_frozen_funds, v_summary.total_frozen_funds,
      v_summary.available_funds)
    is distinct from (35000000::bigint, 20000000::bigint, 10000000::bigint, 30000000::bigint, 5000000::bigint) then
    raise exception 'manual credit returned an incorrect GM funds summary';
  end if;

  begin
    update public.financial_transactions
    set amount = 1
    where id = v_first.id;
    raise exception 'manual adjustment transaction was mutable';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;

do $$
declare
  v_function oid := 'public.adjust_owner_funds(uuid,bigint,text,uuid)'::regprocedure;
  v_helper oid := 'public.owner_financial_summary_for_owner(uuid)'::regprocedure;
begin
  if has_function_privilege('public', v_function, 'EXECUTE')
    or has_function_privilege('anon', v_function, 'EXECUTE')
    or has_function_privilege('service_role', v_function, 'EXECUTE')
    or not has_function_privilege('authenticated', v_function, 'EXECUTE') then
    raise exception 'manual adjustment function ACL is incorrect';
  end if;

  if has_function_privilege('public', v_helper, 'EXECUTE')
    or has_function_privilege('anon', v_helper, 'EXECUTE')
    or has_function_privilege('authenticated', v_helper, 'EXECUTE')
    or has_function_privilege('service_role', v_helper, 'EXECUTE') then
    raise exception 'manual adjustment internal summary helper is directly executable';
  end if;
end;
$$;

rollback;
