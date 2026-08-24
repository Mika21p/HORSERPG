do $$
begin
  if (select count(*) from public.horse_health_events where horse_id = '00000000-0000-0000-0000-00000000f621' and status = 'ACTIVE') <> 1 then
    raise exception 'same request concurrent post-race processing created duplicate events';
  end if;
  if (select count(*) from public.horse_health_events where horse_id = '00000000-0000-0000-0000-00000000f622' and status = 'ACTIVE' and event_type = 'POST_RACE'::public.horse_health_event_type) <> 2
    or (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000f622') <> 60
    or exists (
      select 1 from public.horse_health_events a join public.horse_health_events b on b.horse_id = a.horse_id and b.event_sequence = a.event_sequence + 1
      where a.horse_id = '00000000-0000-0000-0000-00000000f622' and a.status = 'ACTIVE'::public.horse_health_event_status and b.status = 'ACTIVE'::public.horse_health_event_status and a.stamina_after is distinct from b.stamina_before
    ) then
    raise exception 'parallel same-Horse results did not serialize into a continuous stamina chain';
  end if;
  if (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000f623') <> 50
    or exists (
      select 1 from public.horse_health_events a join public.horse_health_events b on b.horse_id = a.horse_id and b.event_sequence = a.event_sequence + 1
      where a.horse_id = '00000000-0000-0000-0000-00000000f623' and a.status = 'ACTIVE'::public.horse_health_event_status and b.status = 'ACTIVE'::public.horse_health_event_status and a.stamina_after is distinct from b.stamina_before
    ) then
    raise exception 'manual versus post-race concurrency forked the stamina chain';
  end if;
  if not exists (select 1 from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f624' and status = 'VOIDED')
    or exists (select 1 from public.horse_health_events where horse_id = '00000000-0000-0000-0000-00000000f624' and event_type = 'POST_RACE'::public.horse_health_event_type and status = 'ACTIVE') then
    raise exception 'record-versus-void concurrency left an invalid result/health pair';
  end if;
  if not exists (select 1 from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f625' and status = 'VOIDED')
    or exists (select 1 from public.horse_health_events where horse_id = '00000000-0000-0000-0000-00000000f625' and event_type = 'POST_RACE'::public.horse_health_event_type and status = 'ACTIVE')
    or (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000f625') <> 65 then
    raise exception 'void-versus-manual concurrency broke final Horse state';
  end if;
  if not exists (select 1 from public.race_results where horse_id = '00000000-0000-0000-0000-00000000f626' and status = 'VOIDED')
    or exists (
      select 1 from public.horse_health_events
      where horse_id = '00000000-0000-0000-0000-00000000f626'
        and event_type = 'POST_RACE'::public.horse_health_event_type
        and status = 'ACTIVE'::public.horse_health_event_status
    )
    or (select current_stamina from public.horses where id = '00000000-0000-0000-0000-00000000f626') <> 100 then
    raise exception 'correction-versus-result-void concurrency left an invalid health/result state';
  end if;
end;
$$;
