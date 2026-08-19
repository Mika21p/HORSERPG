-- Safe, private projection connecting a PLAYER's own original race-entry
-- request with the GM-authoritative confirmed schedule that resolved it.
-- This deliberately does not change the globally readable public schedule.

begin;

create function public.get_current_player_race_entry_resolutions()
returns table (
  request_id uuid,
  confirmed_entry_id uuid,
  wp_year integer,
  wp_month smallint,
  wp_week smallint,
  race_kind public.race_entry_race_kind,
  race_catalog_id uuid,
  race_label text,
  jockey text,
  running_style text,
  confirmed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if auth.uid() is null then
    raise exception 'only a PLAYER with an Owner may read race-entry resolutions'
      using errcode = '42501';
  end if;

  select profile.owner_id
  into v_owner_id
  from public.user_profiles as profile
  where profile.id = auth.uid()
    and profile.role = 'PLAYER'::public.app_role
    and profile.owner_id is not null
  for key share;

  if not found then
    raise exception 'only a PLAYER with an Owner may read race-entry resolutions'
      using errcode = '42501';
  end if;

  return query
  select
    request.id,
    entry.id,
    entry.wp_year,
    entry.wp_month,
    entry.wp_week,
    entry.race_kind,
    entry.race_catalog_id,
    entry.race_label,
    entry.jockey,
    entry.running_style,
    entry.confirmed_at
  from public.race_entry_requests as request
  join public.confirmed_race_entries as entry
    on entry.request_id = request.id
  where request.owner_id = v_owner_id
    and request.status = 'CONFIRMED'::public.race_entry_request_status;
end;
$$;

revoke all on function public.get_current_player_race_entry_resolutions()
  from public, anon, authenticated, service_role;
grant execute on function public.get_current_player_race_entry_resolutions()
  to authenticated;

comment on function public.get_current_player_race_entry_resolutions() is
  'PLAYER-only private projection joining the caller Owner''s confirmed race-entry requests to their final public schedule facts. Excludes GM-private fields and GM direct entries.';

commit;
