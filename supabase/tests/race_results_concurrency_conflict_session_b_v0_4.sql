begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000e103', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
begin
  begin
    perform public.record_race_result(
      (select id from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-00000000e302'),
      (select id from public.actual_races where race_catalog_id = '00000000-0000-0000-0000-00000000e401'),
      3::smallint, 1000000::bigint, null, null, null
    );
    raise exception 'different concurrent race-result facts were accepted' using errcode = 'XX000';
  exception when raise_exception then
    if sqlerrm not like '%use correction flow%' then raise; end if;
  end;
end;
$$;
commit;
