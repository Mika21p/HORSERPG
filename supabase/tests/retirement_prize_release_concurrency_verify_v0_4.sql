do $$
begin
  if exists (
    select 1
    from public.horses as horse
    join public.prize_receivables as receivable on receivable.horse_id = horse.id
    where horse.id in (
      '00000000-0000-0000-0000-00000000ec20',
      '00000000-0000-0000-0000-00000000ec21',
      '00000000-0000-0000-0000-00000000ec22'
    )
      and horse.life_stage = 'RETIRED'::public.horse_life_stage
      and receivable.status = 'PENDING'::public.prize_receivable_status
  ) then
    raise exception 'retirement concurrency left a retired Horse with pending prize money';
  end if;

  if (select coalesce(sum(entry_row.amount_delta), 0)
      from public.prize_receivable_ledger_entries as entry_row
      join public.prize_receivables as receivable on receivable.id = entry_row.prize_receivable_id
      where receivable.horse_id = '00000000-0000-0000-0000-00000000ec20') <> 15000000
    or (select amount from public.prize_receivables
        where horse_id = '00000000-0000-0000-0000-00000000ec20'
          and status = 'RELEASED'::public.prize_receivable_status) <> 15000000 then
    raise exception 'confirm-vs-correction did not converge to final prize amount';
  end if;

  if (select coalesce(sum(entry_row.amount_delta), 0)
      from public.prize_receivable_ledger_entries as entry_row
      join public.prize_receivables as receivable on receivable.id = entry_row.prize_receivable_id
      where receivable.horse_id = '00000000-0000-0000-0000-00000000ec21') <> 0
    or not exists (
      select 1 from public.prize_receivables
      where horse_id = '00000000-0000-0000-0000-00000000ec21'
        and status = 'CANCELLED'::public.prize_receivable_status
    ) then
    raise exception 'confirm-vs-void did not converge to zero and CANCELLED';
  end if;

  if not exists (
    select 1 from public.prize_receivables
    where horse_id = '00000000-0000-0000-0000-00000000ec22'
      and amount = 13000000
      and status = 'RELEASED'::public.prize_receivable_status
  ) then
    raise exception 'confirm-vs-record did not immediately release the late result';
  end if;

  if (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000ec23')
      <> 'RETIRED'::public.horse_life_stage
    or (select life_stage from public.horses where id = '00000000-0000-0000-0000-00000000ec24')
      <> 'RETIRED'::public.horse_life_stage then
    raise exception 'different-horse retirement confirmations did not both complete';
  end if;
end;
$$;
