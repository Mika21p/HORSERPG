-- Local-only verification for HorseRPG v0.5-A breeding candidates, pedigree
-- references, and controlled Foal creation. Run after `supabase db reset`.
-- Fixtures run in one transaction and are rolled back at the end.

begin;

do $$
declare
  v_function text;
begin
  if not exists (
    select 1 from pg_type as type_row
    join pg_namespace as namespace_row on namespace_row.oid = type_row.typnamespace
    where namespace_row.nspname = 'public'
      and type_row.typname = 'breeding_candidate_type'
  ) or not exists (
    select 1 from pg_type as type_row
    join pg_namespace as namespace_row on namespace_row.oid = type_row.typnamespace
    where namespace_row.nspname = 'public'
      and type_row.typname = 'pedigree_parent_source_type'
  ) then
    raise exception 'v0.5-A pedigree enums are missing';
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'horses' and column_name = 'dam_name'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'horses' and column_name = 'sire_horse_id'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'horses' and column_name = 'dam_reference_id'
  ) then
    raise exception 'v0.5-A Horse pedigree fields are missing';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.breeding_candidates'::regclass
      and contype = 'u'
  ) then
    raise exception 'breeding_candidates must retain a unique Horse identity';
  end if;

  if not (
    select relrowsecurity from pg_class where oid = 'public.breeding_candidates'::regclass
  ) or not (
    select relrowsecurity from pg_class where oid = 'public.pedigree_reference_horses'::regclass
  ) or not (
    select relrowsecurity from pg_class where oid = 'public.foal_creation_requests'::regclass
  ) then
    raise exception 'all v0.5-A public tables must enable RLS';
  end if;

  if not exists (
    select 1 from pg_views
    where schemaname = 'public' and viewname = 'breeding_candidates_public'
  ) or not exists (
    select 1 from pg_views
    where schemaname = 'public' and viewname = 'pedigree_reference_horses_public'
  ) then
    raise exception 'v0.5-A safe public pedigree projections are missing';
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name in ('breeding_candidates_public', 'pedigree_reference_horses_public')
      and column_name in (
        'added_by_user_id', 'deactivated_by_user_id',
        'created_by_user_id', 'updated_by_user_id', 'notes'
      )
  ) then
    raise exception 'a safe public pedigree projection exposes GM metadata or notes';
  end if;

  foreach v_function in array array[
    'public.activate_breeding_candidate(uuid,text)'::text,
    'public.deactivate_breeding_candidate(uuid,text)'::text,
    'public.create_pedigree_reference_horse(text,text,text,text,text,text,text,text[],text)'::text,
    'public.update_pedigree_reference_horse(uuid,text,text,text,text,text,text,text,text[],text)'::text,
    'public.deactivate_pedigree_reference_horse(uuid,text)'::text,
    'public.create_foal(uuid,bigint,integer,text,text,text,text,text,public.pedigree_parent_source_type,uuid,uuid,text,text,public.pedigree_parent_source_type,uuid,uuid,text,text)'::text
  ] loop
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
      raise exception 'v0.5-A RPC has an incorrect security definition or ACL: %', v_function;
    end if;
  end loop;

  foreach v_function in array array[
    'public.enforce_breeding_candidate_horse_eligibility()'::text,
    'public.prevent_foal_creation_request_mutation()'::text,
    'public.prevent_horse_parent_identity_mutation()'::text,
    'public.horse_canonical_registered_name(public.horses)'::text,
    'public.breeding_candidate_audit_data(public.breeding_candidates)'::text,
    'public.pedigree_reference_horse_audit_data(public.pedigree_reference_horses)'::text
  ] loop
    if has_function_privilege('public', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('anon', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('authenticated', v_function::regprocedure, 'EXECUTE')
      or has_function_privilege('service_role', v_function::regprocedure, 'EXECUTE') then
      raise exception 'v0.5-A helper is client-callable: %', v_function;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.breeding_candidates', 'INSERT')
    or has_table_privilege('authenticated', 'public.breeding_candidates', 'UPDATE')
    or has_table_privilege('authenticated', 'public.breeding_candidates', 'DELETE')
    or has_table_privilege('authenticated', 'public.pedigree_reference_horses', 'INSERT')
    or has_table_privilege('authenticated', 'public.pedigree_reference_horses', 'UPDATE')
    or has_table_privilege('authenticated', 'public.pedigree_reference_horses', 'DELETE')
    or has_table_privilege('authenticated', 'public.foal_creation_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.foal_creation_requests', 'UPDATE')
    or has_table_privilege('authenticated', 'public.foal_creation_requests', 'DELETE') then
    raise exception 'v0.5-A base tables expose authenticated write privileges';
  end if;

  if has_table_privilege('public', 'public.breeding_candidates_public', 'SELECT')
    or has_table_privilege('anon', 'public.breeding_candidates_public', 'SELECT')
    or has_table_privilege('service_role', 'public.breeding_candidates_public', 'SELECT')
    or not has_table_privilege('authenticated', 'public.breeding_candidates_public', 'SELECT')
    or has_table_privilege('public', 'public.pedigree_reference_horses_public', 'SELECT')
    or has_table_privilege('anon', 'public.pedigree_reference_horses_public', 'SELECT')
    or has_table_privilege('service_role', 'public.pedigree_reference_horses_public', 'SELECT')
    or not has_table_privilege('authenticated', 'public.pedigree_reference_horses_public', 'SELECT') then
    raise exception 'v0.5-A safe public projection ACL is incorrect';
  end if;
end;
$$;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000b501', 'authenticated', 'authenticated', 'breeding-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-00000000b502', 'authenticated', 'authenticated', 'breeding-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now());

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-00000000b601', 'Breeding Test Owner', 100000000);

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-00000000b501', 'PLAYER', '00000000-0000-0000-0000-00000000b601', 'Breeding Player'),
  ('00000000-0000-0000-0000-00000000b502', 'GM', null, 'Breeding GM');

-- This fixture is deliberately privileged only to prepare historical RETIRED
-- Horses. Candidate RPCs below never set this lifecycle guard marker.
select set_config('horserpg.retirement_transition', 'on', true);
insert into public.horses (
  id, horse_number, birth_year, foal_name, sex, coat_color,
  sire_name, sire_line, broodmare_sire_name, life_stage
)
values
  ('00000000-0000-0000-0000-00000000b701', 95001, 2020, 'Internal Sire', 'MALE', 'BAY', 'Paternal Grand Sire', 'Internal Sire Line', 'Internal Sire Dam Sire', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000b702', 95002, 2020, 'Internal Dam', 'FEMALE', 'CHESTNUT', 'Internal Dam Sire', 'Internal Dam Line', 'Internal Dam Dam Sire', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000b703', 95003, 2023, 'Active Male', 'MALE', 'BAY', 'Active Sire', 'Active Line', 'Active BMS', 'ACTIVE'),
  ('00000000-0000-0000-0000-00000000b704', 95004, 2023, 'Pending Female', 'FEMALE', 'BAY', 'Pending Sire', 'Pending Line', 'Pending BMS', 'RETIRE_PENDING'),
  ('00000000-0000-0000-0000-00000000b705', 95005, 2020, 'Retired Gelding', 'GELDING', 'BAY', 'Gelding Sire', 'Gelding Line', 'Gelding BMS', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000b706', 95006, 2020, 'Sex Guard Stallion', 'MALE', 'BAY', 'Guard Sire', 'Guard Line', 'Guard BMS', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000b707', 95007, 2020, 'Sex Guard Broodmare', 'FEMALE', 'BAY', 'Guard Mare Sire', 'Guard Mare Line', 'Guard Mare BMS', 'RETIRED'),
  ('00000000-0000-0000-0000-00000000b708', 95008, 2020, 'Corrupt Guard Stallion', 'MALE', 'BAY', 'Corrupt Sire', 'Corrupt Line', 'Corrupt BMS', 'RETIRED');
select set_config('horserpg.retirement_transition', '', true);

update public.horses
set name_katakana = 'ノーザンリバー',
    translated_name = '北方川流'
where id = '00000000-0000-0000-0000-00000000b701';

update public.horses
set name_katakana = 'メイショウダム',
    translated_name = '名将母马'
where id = '00000000-0000-0000-0000-00000000b702';

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b502', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b701', 'approved stallion');
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b702', 'approved broodmare');

do $$
begin
  if (select candidate_type from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000b701')
      <> 'STALLION'::public.breeding_candidate_type
    or (select candidate_type from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000b702')
      <> 'BROODMARE'::public.breeding_candidate_type
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000b701')
      <> 'RETIRED'::public.horse_life_stage then
    raise exception 'candidate activation did not derive type or preserved RETIRED state';
  end if;
end;
$$;

select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b701', 'ignored retry');
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b706', 'sex guard stallion');
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b707', 'sex guard broodmare');
select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b708', 'corrupt-candidate defense test');

do $$
begin
  if (select count(*) from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000b701') <> 1 then
    raise exception 'candidate activation is not idempotent';
  end if;

  begin
    perform public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b703', null);
    raise exception 'ACTIVE Horse became a candidate';
  exception when sqlstate '23514' then null;
  end;

  begin
    perform public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b704', null);
    raise exception 'RETIRE_PENDING Horse became a candidate';
  exception when sqlstate '23514' then null;
  end;

  begin
    perform public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b705', null);
    raise exception 'GELDING became a candidate';
  exception when sqlstate '23514' then null;
  end;

  begin
    update public.horses set sex = 'FEMALE' where id = '00000000-0000-0000-0000-00000000b706';
    raise exception 'active STALLION accepted MALE to FEMALE sex drift';
  exception when sqlstate '23514' then null;
  end;

  begin
    update public.horses set sex = 'GELDING' where id = '00000000-0000-0000-0000-00000000b706';
    raise exception 'active STALLION accepted MALE to GELDING sex drift';
  exception when sqlstate '23514' then null;
  end;

  begin
    update public.horses set sex = 'MALE' where id = '00000000-0000-0000-0000-00000000b707';
    raise exception 'active BROODMARE accepted FEMALE to MALE sex drift';
  exception when sqlstate '23514' then null;
  end;

  begin
    update public.horses set sex = 'GELDING' where id = '00000000-0000-0000-0000-00000000b707';
    raise exception 'active BROODMARE accepted FEMALE to GELDING sex drift';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

select public.deactivate_breeding_candidate('00000000-0000-0000-0000-00000000b706', 'allow historical sex correction');
update public.horses
set sex = 'FEMALE'
where id = '00000000-0000-0000-0000-00000000b706';

-- The trigger independently rejects a bad type even for privileged imports.
reset role;
do $$
begin
  begin
    insert into public.breeding_candidates (horse_id, candidate_type)
    values ('00000000-0000-0000-0000-00000000b701', 'BROODMARE'::public.breeding_candidate_type);
    raise exception 'wrong Horse sex candidate type was accepted';
  exception when sqlstate '23514' or unique_violation then
    if sqlstate = 'unique_violation' then
      -- Existing candidate proves the RPC has already selected the only legal type;
      -- test the trigger with the distinct retired mare below instead.
      begin
        insert into public.breeding_candidates (horse_id, candidate_type)
        values ('00000000-0000-0000-0000-00000000b702', 'STALLION'::public.breeding_candidate_type);
        raise exception 'wrong mare candidate type was accepted';
      exception when sqlstate '23514' then null;
      end;
    end if;
  end;
end;
$$;

-- The SQL function checks Horse.sex again even if an out-of-band privileged
-- mistake has left a stale active candidate record behind.
alter table public.horses disable trigger horses_prevent_parent_identity_mutation;
update public.horses
set sex = 'FEMALE'
where id = '00000000-0000-0000-0000-00000000b708';
alter table public.horses enable trigger horses_prevent_parent_identity_mutation;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b502', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.create_foal(
      '00000000-0000-0000-0000-00000000b800', 95100, 2030, 'Corrupt Candidate Rejected', null, null, 'MALE', 'BAY',
      'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b708', null, null, null,
      'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Corrupt Dam', 'Manual Corrupt Dam Sire'
    );
    raise exception 'create_foal accepted stale candidate with incompatible Horse sex';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

select public.create_pedigree_reference_horse(
  'Reference Sire', 'Reference Sire EN', 'MALE', 'Reference Sire Line',
  null, null, null, array['Ref Sire', 'Reference Sire'], 'active sire reference'
);
select public.create_pedigree_reference_horse(
  'Reference Dam', 'Reference Dam EN', 'FEMALE', null,
  'Reference Dam Sire', null, null, array['Ref Dam', 'Reference Dam'], 'active dam reference'
);
select public.create_pedigree_reference_horse(
  'Inactive Reference', null, 'MALE', 'Inactive Line', null, null, null, '{}'::text[], null
);

select set_config('test.breeding.reference_sire_id', (
  select id::text from public.pedigree_reference_horses where name = 'Reference Sire'
), true);
select set_config('test.breeding.reference_dam_id', (
  select id::text from public.pedigree_reference_horses where name = 'Reference Dam'
), true);
select set_config('test.breeding.reference_inactive_id', (
  select id::text from public.pedigree_reference_horses where name = 'Inactive Reference'
), true);

select public.update_pedigree_reference_horse(
  current_setting('test.breeding.reference_sire_id', true)::uuid,
  'Reference Sire', 'Reference Sire Version A', 'MALE', 'Reference Sire Line',
  null, null, null, array['Reference Sire', 'Ref Sire'], 'updated reference'
);
select public.deactivate_pedigree_reference_horse(
  current_setting('test.breeding.reference_inactive_id', true)::uuid, 'not currently offered'
);

do $$
begin
  if (select aliases from public.pedigree_reference_horses
      where id = current_setting('test.breeding.reference_sire_id', true)::uuid)
      <> array['Ref Sire', 'Reference Sire']::text[] then
    raise exception 'reference aliases were not normalized deterministically';
  end if;
end;
$$;

-- GM's legacy Horse CRUD remains available, but it cannot bypass the Foal
-- creation boundary for any structured parent source.
do $$
begin
  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, sex, coat_color,
      sire_name, sire_line, dam_name, broodmare_sire_name,
      sire_parent_source_type, dam_parent_source_type, sire_horse_id
    ) values (
      95020, 2030, 'Blocked Direct Internal', 'MALE', 'BAY',
      'Blocked Sire', 'Blocked Line', 'Blocked Dam', 'Blocked BMS',
      'INTERNAL'::public.pedigree_parent_source_type, 'MANUAL'::public.pedigree_parent_source_type,
      '00000000-0000-0000-0000-00000000b701'
    );
    raise exception 'GM directly inserted a structured INTERNAL pedigree Horse';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, sex, coat_color,
      sire_name, sire_line, dam_name, broodmare_sire_name,
      sire_parent_source_type, dam_parent_source_type, sire_reference_id
    ) values (
      95021, 2030, 'Blocked Direct Reference', 'MALE', 'BAY',
      'Blocked Sire', 'Blocked Line', 'Blocked Dam', 'Blocked BMS',
      'REFERENCE'::public.pedigree_parent_source_type, 'MANUAL'::public.pedigree_parent_source_type,
      current_setting('test.breeding.reference_sire_id', true)::uuid
    );
    raise exception 'GM directly inserted a structured REFERENCE pedigree Horse';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, sex, coat_color,
      sire_name, sire_line, dam_name, broodmare_sire_name,
      sire_parent_source_type, dam_parent_source_type
    ) values (
      95022, 2030, 'Blocked Direct Manual', 'MALE', 'BAY',
      'Blocked Sire', 'Blocked Line', 'Blocked Dam', 'Blocked BMS',
      'MANUAL'::public.pedigree_parent_source_type, 'MANUAL'::public.pedigree_parent_source_type
    );
    raise exception 'GM directly inserted a structured MANUAL pedigree Horse';
  exception when insufficient_privilege then null;
  end;

  insert into public.horses (
    horse_number, birth_year, foal_name, sex, coat_color,
    sire_name, sire_line, dam_name, broodmare_sire_name
  ) values (
    95023, 2030, 'Legacy Horse Still Allowed', 'MALE', 'BAY',
    'Legacy Sire', 'Legacy Line', 'Legacy Dam', 'Legacy BMS'
  );

  update public.horses
  set sire_name = 'Legacy Sire Corrected',
      sire_line = 'Legacy Line Corrected',
      dam_name = 'Legacy Dam Corrected',
      broodmare_sire_name = 'Legacy BMS Corrected'
  where horse_number = 95023;

  if (select sire_parent_source_type is null
        and dam_parent_source_type is null
        and sire_horse_id is null
        and dam_horse_id is null
        and sire_reference_id is null
        and dam_reference_id is null
        and sire_name = 'Legacy Sire Corrected'
        and dam_name = 'Legacy Dam Corrected'
      from public.horses where horse_number = 95023) is not true then
    raise exception 'legacy Horse CRUD was incorrectly restricted';
  end if;
end;
$$;

-- All nine allowed source pairs are accepted. Each one persists text snapshots
-- and a structured source identity without creating a mating record.
select set_config('test.breeding.foal_internal_internal', (
  select (public.create_foal(
    '00000000-0000-0000-0000-00000000b801', 95101, 2030, 'Foal Internal Internal', null, null, 'MALE', 'BAY',
    'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
    'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b702', null, null, null
  )).id::text
), true);

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b802', 95102, 2030, 'Foal Internal Reference', null, null, 'FEMALE', 'BAY',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_dam_id', true)::uuid, null, null
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b803', 95103, 2030, 'Foal Reference Internal', null, null, 'MALE', 'BAY',
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_sire_id', true)::uuid, null, null,
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b702', null, null, null
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b804', 95104, 2030, 'Foal Reference Reference', null, null, 'FEMALE', 'BAY',
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_sire_id', true)::uuid, null, null,
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_dam_id', true)::uuid, null, null
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b805', 95105, 2030, 'Foal Manual Manual', null, null, 'MALE', 'BAY',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Sire', 'Manual Sire Line',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Dam', 'Manual Dam Sire'
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b806', 95106, 2030, 'Foal Internal Manual', null, null, 'FEMALE', 'BAY',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Dam Two', 'Manual Dam Sire Two'
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b807', 95107, 2030, 'Foal Manual Internal', null, null, 'MALE', 'BAY',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Sire Two', 'Manual Sire Line Two',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b702', null, null, null
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b808', 95108, 2030, 'Foal Reference Manual', null, null, 'FEMALE', 'BAY',
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_sire_id', true)::uuid, null, null,
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Dam Three', 'Manual Dam Sire Three'
)).id;

select (public.create_foal(
  '00000000-0000-0000-0000-00000000b809', 95109, 2030, 'Foal Manual Reference', null, null, 'MALE', 'BAY',
  'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Sire Three', 'Manual Sire Line Three',
  'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_dam_id', true)::uuid, null, null
)).id;

do $$
declare
  v_foal public.horses%rowtype;
begin
  select * into v_foal
  from public.horses
  where id = current_setting('test.breeding.foal_internal_internal', true)::uuid;

  if v_foal.life_stage <> 'FOAL'::public.horse_life_stage
    or v_foal.owner_id is not null
    or v_foal.sire_horse_id <> '00000000-0000-0000-0000-00000000b701'
    or v_foal.dam_horse_id <> '00000000-0000-0000-0000-00000000b702'
    or v_foal.sire_name <> 'ノーザンリバー'
    or v_foal.sire_line <> 'Internal Sire Line'
    or v_foal.dam_name <> 'メイショウダム'
    or v_foal.broodmare_sire_name <> 'Internal Dam Sire' then
    raise exception 'INTERNAL canonical parent snapshots or unowned FOAL state are incorrect';
  end if;

  if v_foal.sire_name = 'Internal Sire' or v_foal.dam_name = 'Internal Dam' then
    raise exception 'internal parent Foal snapshot used a foal-stage name instead of canonical registered name';
  end if;

  if (select count(*) from public.horses where horse_number between 95101 and 95109) <> 9 then
    raise exception 'not every legal pedigree source pair created a Foal';
  end if;

  if exists (
    select 1 from public.horse_factors
    where horse_id = v_foal.id
  ) then
    raise exception 'Foal creation must not auto-inherit Horse factors';
  end if;

  begin
    insert into public.horses (
      horse_number, birth_year, foal_name, sex, coat_color,
      sire_name, sire_line, dam_name, broodmare_sire_name,
      sire_parent_source_type, dam_parent_source_type
    ) values (
      95120, 2030, 'Marker Must Be Closed', 'MALE', 'BAY',
      'Marker Sire', 'Marker Line', 'Marker Dam', 'Marker BMS',
      'MANUAL'::public.pedigree_parent_source_type, 'MANUAL'::public.pedigree_parent_source_type
    );
    raise exception 'create_foal left its structured INSERT marker enabled';
  exception when insufficient_privilege then null;
  end;
end;
$$;

-- Repeating a successful request returns the original Horse even after its
-- internal parent is deactivated. A different fact set remains a conflict.
select public.deactivate_breeding_candidate('00000000-0000-0000-0000-00000000b701', 'temporary pause');
select (public.create_foal(
  '00000000-0000-0000-0000-00000000b801', 95101, 2030, 'Foal Internal Internal', null, null, 'MALE', 'BAY',
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
  'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b702', null, null, null
)).id;

do $$
begin
  if (select count(*) from public.horses where horse_number = 95101) <> 1
    or (select count(*) from public.foal_creation_requests where request_id = '00000000-0000-0000-0000-00000000b801') <> 1 then
    raise exception 'same request id created duplicate Foal facts';
  end if;

  begin
    perform public.create_foal(
      '00000000-0000-0000-0000-00000000b801', 95101, 2030, 'Different Fact', null, null, 'MALE', 'BAY',
      'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
      'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b702', null, null, null
    );
    raise exception 'same request id accepted different Foal facts';
  exception when unique_violation then null;
  end;

  begin
    perform public.create_foal(
      '00000000-0000-0000-0000-00000000b80a', 95110, 2030, 'Inactive Candidate Fail', null, null, 'MALE', 'BAY',
      'INTERNAL'::public.pedigree_parent_source_type, '00000000-0000-0000-0000-00000000b701', null, null, null,
      'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Dam Fail', 'Manual Dam Sire Fail'
    );
    raise exception 'inactive candidate created a Foal';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

reset role;
do $$
begin
  begin
    update public.foal_creation_requests
    set request_facts = '{}'::jsonb
    where request_id = '00000000-0000-0000-0000-00000000b801';
    raise exception 'Foal creation request ledger accepted a mutation';
  exception when sqlstate '55000' then null;
  end;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b502', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b701', 'reactivated');
select public.deactivate_pedigree_reference_horse(
  current_setting('test.breeding.reference_inactive_id', true)::uuid, 'idempotent retry'
);

do $$
begin
  begin
    perform public.create_foal(
      '00000000-0000-0000-0000-00000000b80b', 95111, 2030, 'Inactive Reference Fail', null, null, 'MALE', 'BAY',
      'REFERENCE'::public.pedigree_parent_source_type, null, current_setting('test.breeding.reference_inactive_id', true)::uuid, null, null,
      'MANUAL'::public.pedigree_parent_source_type, null, null, 'Manual Dam Fail Ref', 'Manual Dam Sire Fail Ref'
    );
    raise exception 'inactive reference created a Foal';
  exception when sqlstate '23514' then null;
  end;
end;
$$;

-- Reference edits never rewrite the historical Foal snapshot; direct parent
-- identity updates are also rejected until a future correction flow exists.
select public.update_pedigree_reference_horse(
  current_setting('test.breeding.reference_dam_id', true)::uuid,
  'Reference Dam Changed', 'Reference Dam Version B', 'FEMALE', null,
  'Reference Dam Sire Changed', null, null, array['Reference Dam Changed'], 'changed after Foal'
);

do $$
begin
  if (select dam_name from public.horses where horse_number = 95102) <> 'Reference Dam'
    or (select broodmare_sire_name from public.horses where horse_number = 95102) <> 'Reference Dam Sire' then
    raise exception 'reference edit rewrote a Foal snapshot';
  end if;

  begin
    update public.horses set sire_name = 'Uncontrolled sire correction' where horse_number = 95101;
    raise exception 'structured Foal allowed direct sire_name mutation';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.horses set sire_line = 'Uncontrolled line correction' where horse_number = 95101;
    raise exception 'structured Foal allowed direct sire_line mutation';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.horses set dam_name = 'Uncontrolled dam correction' where horse_number = 95101;
    raise exception 'structured Foal allowed direct dam_name mutation';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.horses set broodmare_sire_name = 'Uncontrolled broodmare sire correction' where horse_number = 95101;
    raise exception 'structured Foal allowed direct broodmare_sire_name mutation';
  exception when insufficient_privilege then null;
  end;

  begin
    update public.horses set sire_horse_id = null where horse_number = 95101;
    raise exception 'structured Foal allowed direct sire parent mutation';
  exception when insufficient_privilege then null;
  end;
end;
$$;

select public.deactivate_breeding_candidate(
  '00000000-0000-0000-0000-00000000b701', 'hide inactive candidate from PLAYER'
);

-- A PLAYER sees only active candidate/reference material and has no business
-- write path. GM sees inactive history and the idempotency ledger.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b501', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if exists (
    select 1 from public.breeding_candidates
  ) or exists (
    select 1 from public.pedigree_reference_horses
  ) or exists (select 1 from public.foal_creation_requests) then
    raise exception 'PLAYER can read a sensitive pedigree base table or Foal request ledger';
  end if;

  if not exists (
    select 1 from public.breeding_candidates_public
    where horse_id = '00000000-0000-0000-0000-00000000b702'
      and candidate_type = 'BROODMARE'::public.breeding_candidate_type
  ) or not exists (
    select 1 from public.pedigree_reference_horses_public
    where id = current_setting('test.breeding.reference_sire_id', true)::uuid
      and name = 'Reference Sire'
  ) then
    raise exception 'PLAYER cannot read active safe public pedigree data';
  end if;

  if exists (
    select 1 from public.breeding_candidates_public
    where horse_id = '00000000-0000-0000-0000-00000000b701'
  ) or exists (
    select 1 from public.pedigree_reference_horses_public
    where id = current_setting('test.breeding.reference_inactive_id', true)::uuid
  ) then
    raise exception 'PLAYER can read inactive pedigree material through a public projection';
  end if;

  begin
    execute 'select added_by_user_id from public.breeding_candidates_public';
    raise exception 'PLAYER public candidate projection exposed actor metadata';
  exception when undefined_column then null;
  end;

  begin
    execute 'select created_by_user_id, updated_by_user_id, notes from public.pedigree_reference_horses_public';
    raise exception 'PLAYER public reference projection exposed GM metadata or notes';
  exception when undefined_column then null;
  end;

  begin
    perform public.activate_breeding_candidate('00000000-0000-0000-0000-00000000b701', null);
    raise exception 'PLAYER activated a breeding candidate';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.create_pedigree_reference_horse('PLAYER Reference', null, null, null, null, null, null, null, null);
    raise exception 'PLAYER created a reference';
  exception when insufficient_privilege then null;
  end;

  begin
    perform public.create_foal(
      '00000000-0000-0000-0000-00000000b80c', 95112, 2030, 'Player Foal', null, null, 'MALE', 'BAY',
      'MANUAL'::public.pedigree_parent_source_type, null, null, 'Player Manual Sire', 'Player Manual Line',
      'MANUAL'::public.pedigree_parent_source_type, null, null, 'Player Manual Dam', 'Player Manual BMS'
    );
    raise exception 'PLAYER created a Foal';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.pedigree_reference_horses (name) values ('PLAYER direct write');
    raise exception 'PLAYER directly inserted a reference';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000b502', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  if not exists (
    select 1 from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000b701'
  ) or not exists (
    select 1 from public.pedigree_reference_horses
    where id = current_setting('test.breeding.reference_inactive_id', true)::uuid
  ) or not exists (select 1 from public.foal_creation_requests) then
    raise exception 'GM cannot read the required inactive/history rows';
  end if;

  if (select added_by_user_id from public.breeding_candidates
      where horse_id = '00000000-0000-0000-0000-00000000b701')
      <> '00000000-0000-0000-0000-00000000b502'::uuid
    or (select created_by_user_id from public.pedigree_reference_horses
        where id = current_setting('test.breeding.reference_sire_id', true)::uuid)
        <> '00000000-0000-0000-0000-00000000b502'::uuid then
    raise exception 'GM base access did not retain the expected actor metadata';
  end if;

  if (select count(*) from public.audit_logs
      where action in (
        'BREEDING_CANDIDATE_ACTIVATED', 'BREEDING_CANDIDATE_DEACTIVATED',
        'PEDIGREE_REFERENCE_CREATED', 'PEDIGREE_REFERENCE_UPDATED',
        'PEDIGREE_REFERENCE_DEACTIVATED', 'FOAL_CREATED'
      )) < 6 then
    raise exception 'v0.5-A actions did not write audit records';
  end if;
end;
$$;

reset role;
rollback;
