do $$
declare
  v_same_entry_id uuid;
  v_conflict_entry_id uuid;
  v_actual_race_id uuid;
begin
  select id into v_same_entry_id from public.confirmed_race_entries
  where horse_id = '00000000-0000-0000-0000-00000000e301';
  select id into v_conflict_entry_id from public.confirmed_race_entries
  where horse_id = '00000000-0000-0000-0000-00000000e302';
  select id into v_actual_race_id from public.actual_races
  where race_catalog_id = '00000000-0000-0000-0000-00000000e401';

  if (select count(*) from public.race_results
      where confirmed_race_entry_id = v_same_entry_id
        and status = 'CONFIRMED'::public.race_result_status) <> 1
    or (select count(*)
        from public.prize_receivables as receivable
        join public.race_results as result on result.id = receivable.race_result_id
        where result.confirmed_race_entry_id = v_same_entry_id) <> 1
    or (select count(*) from public.audit_logs
        where action = 'RACE_RESULT_RECORDED'
          and entity_id = (select id::text from public.race_results where confirmed_race_entry_id = v_same_entry_id and status = 'CONFIRMED'::public.race_result_status)) <> 1 then
    raise exception 'same-facts concurrent retries did not produce exactly one current result, prize receivable, and record audit';
  end if;

  if (select count(*) from public.race_results
      where confirmed_race_entry_id = v_conflict_entry_id
        and status = 'CONFIRMED'::public.race_result_status) <> 1
    or (select count(*)
        from public.prize_receivables as receivable
        join public.race_results as result on result.id = receivable.race_result_id
        where result.confirmed_race_entry_id = v_conflict_entry_id) <> 1
    or not exists (
      select 1 from public.race_results
      where confirmed_race_entry_id = v_conflict_entry_id
        and actual_race_id = v_actual_race_id
        and finish_position = 2
        and prize_amount = 1000000
        and status = 'CONFIRMED'::public.race_result_status
    ) then
    raise exception 'different-facts concurrent submission did not retain exactly the first result';
  end if;
end;
$$;
