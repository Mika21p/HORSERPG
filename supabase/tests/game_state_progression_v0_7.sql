-- Local-only verification for audited Winning Post time progression.
-- Run after applying all migrations. This transaction always rolls back.

begin;

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000701', 'authenticated', 'authenticated', 'time-player@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now()),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000702', 'authenticated', 'authenticated', 'time-gm@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now())
on conflict (id) do nothing;

insert into public.owners (id, display_name, initial_funds)
values ('00000000-0000-0000-0000-000000000700', 'Time Test Owner', 0)
on conflict (id) do nothing;

insert into public.user_profiles (id, role, owner_id, display_name)
values
  ('00000000-0000-0000-0000-000000000701', 'PLAYER', '00000000-0000-0000-0000-000000000700', 'Time Player'),
  ('00000000-0000-0000-0000-000000000702', 'GM', null, 'Time GM')
on conflict (id) do update set role = excluded.role, owner_id = excluded.owner_id, display_name = excluded.display_name;

delete from public.audit_logs where entity_type = 'game_state' and entity_id = 'current';
delete from public.game_state;

set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000701', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
begin
  begin
    perform public.initialize_game_state(2026, 1, 1);
    raise exception 'PLAYER initialized game state';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.game_state (current_wp_year, current_wp_month, current_wp_week)
    values (2026, 1, 1);
    raise exception 'PLAYER directly inserted game state';
  exception when insufficient_privilege then null;
  end;
end;
$$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000702', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.initialize_game_state(2026, 1, 1);

do $$
declare
  changed integer;
begin
  update public.game_state set current_wp_week = 2 where id = true;
  get diagnostics changed = row_count;
  if changed <> 0 then
    raise exception 'GM directly updated game state outside the RPC';
  end if;
end;
$$;

select public.advance_game_state_one_week(2026, 1, 1);

do $$
begin
  begin
    perform public.advance_game_state_one_week(2026, 1, 1);
    raise exception 'stale expected time was accepted';
  exception when serialization_failure then null;
  end;

  begin
    perform public.correct_game_state(2026, 1, 2, 2026, 1, 5, '', 'CORRECT WP TIME');
    raise exception 'empty correction reason was accepted';
  exception when invalid_parameter_value then null;
  end;

  begin
    perform public.correct_game_state(2026, 1, 2, 2026, 1, 5, 'boundary test', 'WRONG');
    raise exception 'incorrect confirmation was accepted';
  exception when invalid_parameter_value then null;
  end;
end;
$$;

select public.correct_game_state(2026, 1, 2, 2026, 1, 5, 'month boundary test', 'CORRECT WP TIME');
select public.advance_game_state_one_week(2026, 1, 5);

do $$
declare
  current_state public.game_state%rowtype;
begin
  select * into current_state from public.game_state where id = true;
  if (current_state.current_wp_year, current_state.current_wp_month, current_state.current_wp_week)
    is distinct from (2026, 2, 1) then
    raise exception 'month boundary advance produced %.%.%', current_state.current_wp_year, current_state.current_wp_month, current_state.current_wp_week;
  end if;
end;
$$;

select public.correct_game_state(2026, 2, 1, 2026, 12, 5, 'year boundary test', 'CORRECT WP TIME');
select public.advance_game_state_one_week(2026, 12, 5);

do $$
declare
  current_state public.game_state%rowtype;
  audit_count integer;
begin
  select * into current_state from public.game_state where id = true;
  if (current_state.current_wp_year, current_state.current_wp_month, current_state.current_wp_week)
    is distinct from (2027, 1, 1) then
    raise exception 'year boundary advance produced %.%.%', current_state.current_wp_year, current_state.current_wp_month, current_state.current_wp_week;
  end if;

  select count(*) into audit_count
  from public.audit_logs
  where entity_type = 'game_state'
    and entity_id = 'current'
    and action in ('GAME_STATE_INITIALIZED', 'GAME_STATE_ADVANCED', 'GAME_STATE_CORRECTED');

  if audit_count <> 6 then
    raise exception 'expected 6 game-state audit rows, got %', audit_count;
  end if;
end;
$$;

rollback;
