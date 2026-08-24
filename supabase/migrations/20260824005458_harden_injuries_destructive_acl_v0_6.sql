begin;

revoke delete on table public.injuries
from public, anon, authenticated, service_role;

revoke truncate on table public.injuries
from public, anon, authenticated, service_role;

commit;
