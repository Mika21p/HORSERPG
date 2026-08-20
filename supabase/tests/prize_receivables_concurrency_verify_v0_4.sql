do $$
declare
  v_result_id uuid;
  v_receivable public.prize_receivables%rowtype;
begin
  select id
  into v_result_id
  from public.race_results
  where horse_id = '00000000-0000-0000-0000-00000000fa30';

  select *
  into v_receivable
  from public.prize_receivables
  where race_result_id = v_result_id;

  if not exists (
    select 1 from public.race_results
    where id = v_result_id and status = 'VOIDED'::public.race_result_status
  ) or not found
    or v_receivable.status <> 'CANCELLED'::public.prize_receivable_status
    or v_receivable.amount <> 3000000
    or v_receivable.cancellation_reason <> 'concurrent prize void'
    or (select count(*) from public.audit_logs
        where action = 'PRIZE_RECEIVABLE_ADJUSTED' and entity_id = v_receivable.id::text) <> 1
    or (select count(*) from public.audit_logs
        where action = 'PRIZE_RECEIVABLE_CANCELLED' and entity_id = v_receivable.id::text) <> 1
    or exists (
      select 1 from public.financial_transactions
      where owner_id = '00000000-0000-0000-0000-00000000fa20'
    ) then
    raise exception 'concurrent correction then void left Prize Receivable inconsistent or touched the ledger';
  end if;
end;
$$;
