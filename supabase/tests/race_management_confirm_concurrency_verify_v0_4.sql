-- Verify exactly one authoritative schedule exists and the failed Request
-- still represents unreviewed PENDING player intent.

do $$
begin
  if (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004801' and wp_year = 2040 and wp_month = 6 and wp_week = 2) <> 1
    or (select status from public.race_entry_requests where player_note = 'concurrent request A') <> 'CONFIRMED'::public.race_entry_request_status
    or (select status from public.race_entry_requests where player_note = 'concurrent request B') <> 'PENDING'::public.race_entry_request_status
    or (select count(*) from public.audit_logs where action = 'RACE_ENTRY_CONFIRMED' and entity_id = (select id::text from public.race_entry_requests where player_note = 'concurrent request A')) <> 1
    or exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_CONFIRMED' and entity_id = (select id::text from public.race_entry_requests where player_note = 'concurrent request B')) then
    raise exception 'concurrent Race Management confirmation left inconsistent request or schedule facts';
  end if;

  if (select count(*) from public.confirmed_race_entries where horse_id = '00000000-0000-0000-0000-000000004802' and wp_year = 2040 and wp_month = 6 and wp_week = 3) <> 1
    or not exists (
      select 1 from public.confirmed_race_entries
      where horse_id = '00000000-0000-0000-0000-000000004802'
        and request_id is null
    )
    or (select status from public.race_entry_requests where player_note = 'direct versus request concurrency') <> 'PENDING'::public.race_entry_request_status
    or (select count(*) from public.audit_logs where action = 'RACE_ENTRY_DIRECTLY_CONFIRMED' and after_data ->> 'horse_id' = '00000000-0000-0000-0000-000000004802') <> 1
    or exists (select 1 from public.audit_logs where action = 'RACE_ENTRY_CONFIRMED' and entity_id = (select id::text from public.race_entry_requests where player_note = 'direct versus request concurrency')) then
    raise exception 'direct GM versus request confirmation concurrency left inconsistent facts';
  end if;
end;
$$;
