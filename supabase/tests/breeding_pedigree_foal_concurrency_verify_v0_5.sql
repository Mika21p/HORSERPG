do $$
begin
  if (select count(*) from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000c702') <> 1
    or not (select is_active from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000c702') then
    raise exception 'concurrent activation did not converge on one active candidate';
  end if;

  if (select count(*) from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000c701') <> 1
    or (select is_active from public.breeding_candidates where horse_id = '00000000-0000-0000-0000-00000000c701') then
    raise exception 'concurrent deactivation did not converge on one inactive candidate';
  end if;

  if (select count(*) from public.foal_creation_requests where request_id = '00000000-0000-0000-0000-00000000c801') <> 1
    or (select count(*) from public.horses where horse_number = 95951) <> 1 then
    raise exception 'concurrent same-request Foal creation was not exactly once';
  end if;

  if (select count(*) from public.horses where horse_number in (95952, 95953)) <> 2 then
    raise exception 'parallel internal-sire Foal creation did not complete both independent requests';
  end if;
end;
$$;
