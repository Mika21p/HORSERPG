-- Session B starts while Session A holds Event lock. It locks the Lot first,
-- then waits for Event, and must reject reopening after observing CLOSED.
begin;
set local lock_timeout = '4s';
set local statement_timeout = '6s';
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000008202', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.reopen_public_auction_lot(
      (select id from public.public_auction_lots where horse_id = '00000000-0000-0000-0000-000000008301'),
      'Concurrent reopen must observe Event closure'
    );
    raise exception 'concurrent reopen succeeded after Event close' using errcode = 'XX000';
  exception when check_violation then null; when raise_exception then
    if sqlerrm not like '%event must be OPEN%' then raise; end if;
  end;
end;
$$;
commit;
