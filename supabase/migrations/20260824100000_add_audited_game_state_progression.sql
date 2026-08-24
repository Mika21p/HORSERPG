begin;

drop policy if exists game_state_insert_gm on public.game_state;
drop policy if exists game_state_update_gm on public.game_state;

create function public.initialize_game_state(
  p_year integer,
  p_month integer,
  p_week integer
)
returns public.game_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state public.game_state%rowtype;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM can initialize game state'
      using errcode = '42501';
  end if;

  if p_year is null or p_year <= 0
    or p_month is null or p_month not between 1 and 12
    or p_week is null or p_week not between 1 and 5 then
    raise exception 'invalid Winning Post time'
      using errcode = '22023';
  end if;

  if exists (select 1 from public.game_state where id = true) then
    raise exception 'game state is already initialized'
      using errcode = '23514';
  end if;

  insert into public.game_state (
    id, current_wp_year, current_wp_month, current_wp_week, updated_by_user_id
  ) values (
    true, p_year, p_month, p_week, auth.uid()
  )
  returning * into v_state;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'GAME_STATE_INITIALIZED',
    'game_state', 'current', null, to_jsonb(v_state), 'INITIALIZE'
  );

  return v_state;
end;
$$;

create function public.advance_game_state_one_week(
  p_expected_year integer,
  p_expected_month integer,
  p_expected_week integer
)
returns public.game_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.game_state%rowtype;
  v_after public.game_state%rowtype;
  v_next_year integer;
  v_next_month integer;
  v_next_week integer;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM can advance game state'
      using errcode = '42501';
  end if;

  if p_expected_year is null or p_expected_month is null or p_expected_week is null then
    raise exception 'expected Winning Post time is required'
      using errcode = '22023';
  end if;

  select * into v_before
  from public.game_state
  where id = true
  for update;

  if not found then
    raise exception 'game state has not been initialized'
      using errcode = '23514';
  end if;

  if (v_before.current_wp_year, v_before.current_wp_month, v_before.current_wp_week)
    is distinct from (p_expected_year, p_expected_month, p_expected_week) then
    raise exception 'game state changed; refresh before advancing'
      using errcode = '40001';
  end if;

  v_next_year := v_before.current_wp_year;
  v_next_month := v_before.current_wp_month;
  v_next_week := v_before.current_wp_week + 1;

  if v_next_week > 5 then
    v_next_week := 1;
    v_next_month := v_next_month + 1;
  end if;

  if v_next_month > 12 then
    v_next_month := 1;
    v_next_year := v_next_year + 1;
  end if;

  update public.game_state
  set current_wp_year = v_next_year,
      current_wp_month = v_next_month,
      current_wp_week = v_next_week,
      updated_by_user_id = auth.uid()
  where id = true
  returning * into v_after;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'GAME_STATE_ADVANCED',
    'game_state', 'current', to_jsonb(v_before), to_jsonb(v_after), 'ADVANCE_ONE_WEEK'
  );

  return v_after;
end;
$$;

create function public.correct_game_state(
  p_expected_year integer,
  p_expected_month integer,
  p_expected_week integer,
  p_new_year integer,
  p_new_month integer,
  p_new_week integer,
  p_reason text,
  p_confirmation text
)
returns public.game_state
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_before public.game_state%rowtype;
  v_after public.game_state%rowtype;
  v_reason text;
begin
  if auth.uid() is null or not public.is_current_user_gm() then
    raise exception 'only a GM can correct game state'
      using errcode = '42501';
  end if;

  v_reason := nullif(btrim(p_reason), '');
  if v_reason is null then
    raise exception 'a correction reason is required'
      using errcode = '22023';
  end if;

  if p_confirmation is distinct from 'CORRECT WP TIME' then
    raise exception 'strict correction confirmation does not match'
      using errcode = '22023';
  end if;

  if p_expected_year is null or p_expected_month is null or p_expected_week is null
    or p_new_year is null or p_new_year <= 0
    or p_new_month is null or p_new_month not between 1 and 12
    or p_new_week is null or p_new_week not between 1 and 5 then
    raise exception 'invalid Winning Post time'
      using errcode = '22023';
  end if;

  select * into v_before
  from public.game_state
  where id = true
  for update;

  if not found then
    raise exception 'game state has not been initialized'
      using errcode = '23514';
  end if;

  if (v_before.current_wp_year, v_before.current_wp_month, v_before.current_wp_week)
    is distinct from (p_expected_year, p_expected_month, p_expected_week) then
    raise exception 'game state changed; refresh before correcting'
      using errcode = '40001';
  end if;

  if (v_before.current_wp_year, v_before.current_wp_month, v_before.current_wp_week)
    is not distinct from (p_new_year, p_new_month, p_new_week) then
    raise exception 'corrected Winning Post time must be different'
      using errcode = '22023';
  end if;

  update public.game_state
  set current_wp_year = p_new_year,
      current_wp_month = p_new_month,
      current_wp_week = p_new_week,
      updated_by_user_id = auth.uid()
  where id = true
  returning * into v_after;

  insert into public.audit_logs (
    actor_user_id, actor_role, action, entity_type, entity_id,
    before_data, after_data, reason
  ) values (
    auth.uid(), 'GM'::public.app_role, 'GAME_STATE_CORRECTED',
    'game_state', 'current', to_jsonb(v_before), to_jsonb(v_after), v_reason
  );

  return v_after;
end;
$$;

revoke all on function public.initialize_game_state(integer, integer, integer)
from public, anon;
revoke all on function public.advance_game_state_one_week(integer, integer, integer)
from public, anon;
revoke all on function public.correct_game_state(integer, integer, integer, integer, integer, integer, text, text)
from public, anon;

grant execute on function public.initialize_game_state(integer, integer, integer)
to authenticated;
grant execute on function public.advance_game_state_one_week(integer, integer, integer)
to authenticated;
grant execute on function public.correct_game_state(integer, integer, integer, integer, integer, integer, text, text)
to authenticated;

commit;
