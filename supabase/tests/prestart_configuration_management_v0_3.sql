-- Local-only verification for draft-only configuration removal.
-- Run after `npx supabase db reset`; every fixture is rolled back.

begin;

do $$
declare
  v_function regprocedure;
begin
  foreach v_function in array array[
    'public.remove_foal_trade_draft_lot(uuid,text)'::regprocedure,
    'public.remove_foal_trade_draft_session(uuid,text)'::regprocedure,
    'public.remove_public_auction_draft_lot(uuid,text)'::regprocedure,
    'public.remove_public_auction_draft_event(uuid,text)'::regprocedure
  ]
  loop
    if not exists (
      select 1
      from pg_proc as procedure
      where procedure.oid = v_function
        and procedure.prosecdef
        and 'search_path=""' = any(coalesce(procedure.proconfig, array[]::text[]))
    ) then
      raise exception 'draft-removal RPC % is missing SECURITY DEFINER or fixed search_path', v_function;
    end if;

    if not has_function_privilege('authenticated', v_function, 'EXECUTE')
      or has_function_privilege('anon', v_function, 'EXECUTE')
      or has_function_privilege('service_role', v_function, 'EXECUTE')
      or exists (
        select 1
        from pg_proc as procedure
        cross join lateral aclexplode(coalesce(procedure.proacl, acldefault('f', procedure.proowner))) as acl
        where procedure.oid = v_function
          and acl.grantee = 0
          and acl.privilege_type = 'EXECUTE'
      ) then
      raise exception 'draft-removal RPC % ACL is incorrect', v_function;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.foal_trade_lots', 'DELETE')
    or has_table_privilege('authenticated', 'public.foal_trade_sessions', 'DELETE')
    or has_table_privilege('authenticated', 'public.public_auction_lots', 'DELETE')
    or has_table_privilege('authenticated', 'public.public_auction_events', 'DELETE') then
    raise exception 'draft removal must not add direct DELETE privileges';
  end if;
end;
$$;

set local role anon;
do $$
begin
  begin
    perform public.remove_foal_trade_draft_lot(
      '00000000-0000-0000-0000-000000008901', 'anon attempt'
    );
    raise exception 'anon invoked a draft-removal RPC' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000008201', 'authenticated', 'authenticated', 'draft-removal-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000008202', 'authenticated', 'authenticated', 'draft-removal-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000008101', 'Draft Removal Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000008201', 'PLAYER', '00000000-0000-0000-0000-000000008101', 'Draft Removal Player'),
  ('00000000-0000-0000-0000-000000008202', 'GM', null, 'Draft Removal GM');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008201', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.remove_foal_trade_draft_session(
      '00000000-0000-0000-0000-000000008901', 'PLAYER attempt'
    );
    raise exception 'PLAYER removed a foal-trade draft session' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.remove_public_auction_draft_event(
      '00000000-0000-0000-0000-000000008902', 'PLAYER attempt'
    );
    raise exception 'PLAYER removed a public-auction draft event' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name
)
values
  ('00000000-0000-0000-0000-000000008301', 88001, 2081, 'Draft Foal One', 'MALE', 'BAY', 'Sire A', 'Line A', 'Dam Sire A'),
  ('00000000-0000-0000-0000-000000008302', 88002, 2081, 'Draft Foal Two', 'FEMALE', 'CHESTNUT', 'Sire B', 'Line B', 'Dam Sire B'),
  ('00000000-0000-0000-0000-000000008303', 88003, 2081, 'Draft Foal Three', 'MALE', 'BROWN', 'Sire C', 'Line C', 'Dam Sire C'),
  ('00000000-0000-0000-0000-000000008304', 88004, 2082, 'Protected Draft Foal', 'FEMALE', 'GREY', 'Sire D', 'Line D', 'Dam Sire D'),
  ('00000000-0000-0000-0000-000000008305', 88005, 2083, 'Auction Draft Foal One', 'MALE', 'BAY', 'Sire E', 'Line E', 'Dam Sire E'),
  ('00000000-0000-0000-0000-000000008306', 88006, 2084, 'Auction Draft Foal Two', 'FEMALE', 'CHESTNUT', 'Sire F', 'Line F', 'Dam Sire F'),
  ('00000000-0000-0000-0000-000000008307', 88007, 2084, 'Auction Draft Foal Three', 'MALE', 'BROWN', 'Sire G', 'Line G', 'Dam Sire G'),
  ('00000000-0000-0000-0000-000000008308', 88008, 2085, 'Auction Open Event Foal', 'FEMALE', 'GREY', 'Sire H', 'Line H', 'Dam Sire H');

-- A GM may delete a never-started foal-trade Lot and the Horse becomes
-- eligible for a new configuration. Every delete records immutable audit.
insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values ('00000000-0000-0000-0000-000000008401', 2081, clock_timestamp() + interval '1 day', clock_timestamp() + interval '2 days', 'DRAFT');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values ('00000000-0000-0000-0000-000000008411', '00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000008301', 0);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.remove_foal_trade_draft_lot(
  '00000000-0000-0000-0000-000000008411', 'configured for the wrong year'
);
reset role;

do $$
begin
  if exists (select 1 from public.foal_trade_lots where id = '00000000-0000-0000-0000-000000008411')
    or not exists (select 1 from public.horses where id = '00000000-0000-0000-0000-000000008301' and owner_id is null and life_stage = 'FOAL')
    or not exists (
      select 1
      from public.audit_logs
      where action = 'FOAL_TRADE_DRAFT_LOT_REMOVED'
        and entity_id = '00000000-0000-0000-0000-000000008411'
        and reason = 'configured for the wrong year'
    ) then
    raise exception 'eligible foal-trade draft Lot was not removed and audited correctly';
  end if;
end;
$$;

-- Session removal applies the same check to every child Lot and leaves audit
-- facts for each child as well as the former parent Session.
insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values
  ('00000000-0000-0000-0000-000000008412', '00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000008302', 0),
  ('00000000-0000-0000-0000-000000008413', '00000000-0000-0000-0000-000000008401', '00000000-0000-0000-0000-000000008303', 0);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.remove_foal_trade_draft_session(
  '00000000-0000-0000-0000-000000008401', 'replace the entire draft session'
);
reset role;

do $$
begin
  if exists (select 1 from public.foal_trade_sessions where id = '00000000-0000-0000-0000-000000008401')
    or exists (select 1 from public.foal_trade_lots where id in ('00000000-0000-0000-0000-000000008412', '00000000-0000-0000-0000-000000008413'))
    or (select count(*) from public.audit_logs where action = 'FOAL_TRADE_DRAFT_LOT_REMOVED' and entity_id in ('00000000-0000-0000-0000-000000008412', '00000000-0000-0000-0000-000000008413')) <> 2
    or not exists (select 1 from public.audit_logs where action = 'FOAL_TRADE_DRAFT_SESSION_REMOVED' and entity_id = '00000000-0000-0000-0000-000000008401') then
    raise exception 'foal-trade draft session removal did not remove and audit its eligible children';
  end if;
end;
$$;

-- A player intent makes the configuration permanent. Blank reasons are also
-- rejected before any deletion is attempted.
insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values ('00000000-0000-0000-0000-000000008402', 2082, clock_timestamp() + interval '1 day', clock_timestamp() + interval '2 days', 'DRAFT');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price)
values ('00000000-0000-0000-0000-000000008414', '00000000-0000-0000-0000-000000008402', '00000000-0000-0000-0000-000000008304', 0);

insert into public.foal_trade_inquiries (session_id, lot_id, owner_id)
values ('00000000-0000-0000-0000-000000008402', '00000000-0000-0000-0000-000000008414', '00000000-0000-0000-0000-000000008101');

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.remove_foal_trade_draft_lot('00000000-0000-0000-0000-000000008414', '');
    raise exception 'blank removal reason was accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;

  begin
    perform public.remove_foal_trade_draft_lot('00000000-0000-0000-0000-000000008414', 'already has an inquiry');
    raise exception 'foal-trade Lot with player intent was removed' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

-- Establish three valid public-auction candidates via their same-year UNSOLD
-- foal-trade facts. They remain unowned FOALs.
insert into public.foal_trade_sessions (id, wp_year, starts_at, ends_at, status)
values
  ('00000000-0000-0000-0000-000000008403', 2083, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'),
  ('00000000-0000-0000-0000-000000008404', 2084, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN'),
  ('00000000-0000-0000-0000-000000008405', 2085, clock_timestamp() - interval '1 hour', clock_timestamp() + interval '1 hour', 'OPEN');

insert into public.foal_trade_lots (id, session_id, horse_id, minimum_price, status)
values
  ('00000000-0000-0000-0000-000000008421', '00000000-0000-0000-0000-000000008403', '00000000-0000-0000-0000-000000008305', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008422', '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000008306', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008423', '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000008307', 0, 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008424', '00000000-0000-0000-0000-000000008405', '00000000-0000-0000-0000-000000008308', 0, 'UNSOLD');

insert into public.foal_trade_settlements (lot_id, session_id, horse_id, status)
values
  ('00000000-0000-0000-0000-000000008421', '00000000-0000-0000-0000-000000008403', '00000000-0000-0000-0000-000000008305', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008422', '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000008306', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008423', '00000000-0000-0000-0000-000000008404', '00000000-0000-0000-0000-000000008307', 'UNSOLD'),
  ('00000000-0000-0000-0000-000000008424', '00000000-0000-0000-0000-000000008405', '00000000-0000-0000-0000-000000008308', 'UNSOLD');

-- A whole DRAFT public-auction Event can be removed only while every Lot and
-- Round are still pure configuration. Reviews and the initial Round disappear
-- with the Lot, while audit records remain.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2083, 'Draft Lot Removal Event', 100000);
select public.create_public_auction_lot(
  (select id from public.public_auction_events where wp_year = 2083),
  '00000000-0000-0000-0000-000000008305', 1, 100000, 100000
);
select public.upsert_public_auction_lot_review(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008305'),
  1::smallint, 5::smallint, 'draft review'
);
select public.remove_public_auction_draft_lot(
  (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008305'),
  'wrong candidate horse'
);
reset role;

do $$
begin
  if exists (select 1 from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008305')
    or exists (
      select 1
      from public.public_auction_lot_reviews as review
      join public.public_auction_lots as lot on lot.id = review.lot_id
      where lot.horse_id = '00000000-0000-0000-0000-000000008305'
    )
    or exists (
      select 1
      from public.public_auction_rounds as round
      join public.public_auction_lots as lot on lot.id = round.lot_id
      where lot.horse_id = '00000000-0000-0000-0000-000000008305'
    )
    or not exists (
      select 1
      from public.audit_logs
      where action = 'PUBLIC_AUCTION_DRAFT_LOT_REMOVED'
        and reason = 'wrong candidate horse'
    ) then
    raise exception 'eligible public-auction draft Lot was not removed and audited correctly';
  end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2084, 'Draft Event Removal Event', 100000);
select public.create_public_auction_lot((select id from public.public_auction_events where wp_year = 2084), '00000000-0000-0000-0000-000000008306', 1, 100000, 100000);
select public.create_public_auction_lot((select id from public.public_auction_events where wp_year = 2084), '00000000-0000-0000-0000-000000008307', 2, 100000, 100000);
select public.remove_public_auction_draft_event(
  (select id from public.public_auction_events where wp_year = 2084),
  'restart the draft event from scratch'
);
reset role;

do $$
begin
  if exists (select 1 from public.public_auction_events where wp_year = 2084)
    or exists (select 1 from public.public_auction_lots where horse_id in ('00000000-0000-0000-0000-000000008306', '00000000-0000-0000-0000-000000008307'))
    or (select count(*) from public.audit_logs where action = 'PUBLIC_AUCTION_DRAFT_LOT_REMOVED' and reason = 'restart the draft event from scratch') <> 2
    or not exists (select 1 from public.audit_logs where action = 'PUBLIC_AUCTION_DRAFT_EVENT_REMOVED' and reason = 'restart the draft event from scratch') then
    raise exception 'public-auction draft event removal did not remove and audit its eligible children';
  end if;
end;
$$;

-- A live Event is never removable, even if its only Lot is still untouched.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.create_public_auction_event(2085, 'Open Event Cannot Be Removed', 100000);
select public.create_public_auction_lot((select id from public.public_auction_events where wp_year = 2085), '00000000-0000-0000-0000-000000008308', 1, 100000, 100000);
select public.set_public_auction_event_status((select id from public.public_auction_events where wp_year = 2085), 'OPEN'::public.public_auction_event_status);
do $$
begin
  begin
    perform public.remove_public_auction_draft_event(
      (select id from public.public_auction_events where wp_year = 2085),
      'must be rejected after open'
    );
    raise exception 'OPEN public-auction Event was removed' using errcode = 'XX000';
  exception when check_violation then null;
  end;
end;
$$;
reset role;

rollback;
