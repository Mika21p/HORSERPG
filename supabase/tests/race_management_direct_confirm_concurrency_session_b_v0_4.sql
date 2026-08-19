-- Session B: the pending PLAYER request waits for Session A's Horse lock.
-- It must not create a duplicate final schedule and must remain PENDING.

begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000004702', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.confirm_race_entry_request(
      (select id from public.race_entry_requests where player_note = 'direct versus request concurrency'),
      2040, 6::smallint, 3::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, null
    );
    raise exception 'request confirmation unexpectedly duplicated a direct GM schedule' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
end;
$$;
commit;
