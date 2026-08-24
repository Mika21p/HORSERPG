begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000f601', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select public.record_post_race_health('00000000-0000-0000-0000-00000000f713', (select id from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f622' order by recorded_at desc limit 1), 60::smallint, null, null, null, null, null, null, null, 'second parallel result');
commit;
