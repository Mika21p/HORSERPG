-- Local verification for the v0.6 injuries destructive-ACL hardening.
-- Run after `npx supabase db reset`. All fixtures roll back.

begin;

do $$
begin
  if not has_table_privilege('authenticated', 'public.injuries', 'SELECT')
    or not has_table_privilege('authenticated', 'public.injuries', 'INSERT')
    or not has_table_privilege('authenticated', 'public.injuries', 'UPDATE') then
    raise exception 'authenticated lost a required legacy injuries privilege';
  end if;

  if has_table_privilege('authenticated', 'public.injuries', 'DELETE')
    or has_table_privilege('anon', 'public.injuries', 'DELETE')
    or has_table_privilege('service_role', 'public.injuries', 'DELETE')
    or has_table_privilege('authenticated', 'public.injuries', 'TRUNCATE')
    or has_table_privilege('anon', 'public.injuries', 'TRUNCATE')
    or has_table_privilege('service_role', 'public.injuries', 'TRUNCATE') then
    raise exception 'injuries DELETE or TRUNCATE remains effective for a client role';
  end if;

  if exists (
    select 1
    from pg_class as relation
    cross join lateral aclexplode(coalesce(relation.relacl, acldefault('r', relation.relowner))) as privilege
    where relation.oid = 'public.injuries'::regclass
      and privilege.grantee = 0
      and privilege.privilege_type in ('DELETE', 'TRUNCATE')
  ) then
    raise exception 'PUBLIC retains a destructive injuries grant';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ea01', 'authenticated', 'authenticated', 'injury-acl-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000ea02', 'authenticated', 'authenticated', 'injury-acl-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-00000000ea11', 'Injury ACL Player Owner', 0);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000ea01', 'GM', null, 'Injury ACL GM'),
  ('00000000-0000-0000-0000-00000000ea02', 'PLAYER', '00000000-0000-0000-0000-00000000ea11', 'Injury ACL Player');

insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, life_stage
) values (
  '00000000-0000-0000-0000-00000000ea10', 98101, 2040,
  'Injury ACL Fixture Horse', 'MALE', 'BAY',
  'ACL Sire', 'ACL Line', 'ACL Dam', 'ACTIVE'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ea01', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

insert into public.injuries (
  id, horse_id, status,
  wp_start_year, wp_start_month, wp_start_week,
  wp_end_year, wp_end_month, wp_end_week, notes, confirmed_by_user_id
) values (
  '00000000-0000-0000-0000-00000000ea20', '00000000-0000-0000-0000-00000000ea10', 'ACTIVE',
  2040, 1, 1, 2040, 1, 2, 'GM legacy injury insert', '00000000-0000-0000-0000-00000000ea01'
);
update public.injuries
set notes = 'GM legacy injury update'
where id = '00000000-0000-0000-0000-00000000ea20';

do $$
begin
  begin
    delete from public.injuries where id = '00000000-0000-0000-0000-00000000ea20';
    raise exception 'GM direct DELETE was accepted' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000ea02', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_updated integer;
begin
  if (select count(*) from public.injuries where id = '00000000-0000-0000-0000-00000000ea20') <> 1 then
    raise exception 'PLAYER lost legacy injuries SELECT access';
  end if;

  begin
    insert into public.injuries (
      horse_id, status,
      wp_start_year, wp_start_month, wp_start_week,
      wp_end_year, wp_end_month, wp_end_week
    ) values (
      '00000000-0000-0000-0000-00000000ea10', 'ACTIVE',
      2040, 1, 1, 2040, 1, 2
    );
    raise exception 'PLAYER direct INSERT was accepted' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;

  update public.injuries
  set notes = 'PLAYER mutation attempt'
  where id = '00000000-0000-0000-0000-00000000ea20';
  get diagnostics v_updated = row_count;
  if v_updated <> 0 then
    raise exception 'PLAYER direct UPDATE affected a legacy injury';
  end if;

  begin
    delete from public.injuries where id = '00000000-0000-0000-0000-00000000ea20';
    raise exception 'PLAYER direct DELETE was accepted' using errcode = 'XX000';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
rollback;
