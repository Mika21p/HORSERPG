-- Session B must wait for Session A's Horse lock. The final unique index
-- rejects its same-week schedule; the exception subtransaction keeps Request
-- B PENDING and lets the outer session commit normally.

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
      (select id from public.race_entry_requests where player_note = 'concurrent request B'),
      2040, 6::smallint, 2::smallint,
      'CATALOG'::public.race_entry_race_kind, '00000000-0000-0000-0000-000000004901', null, null, null, null
    );
    raise exception 'Session B unexpectedly confirmed a duplicate Horse WP week' using errcode = 'XX000';
  exception when unique_violation then null;
  end;
end;
$$;
commit;
