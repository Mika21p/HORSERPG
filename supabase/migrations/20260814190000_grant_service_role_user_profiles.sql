GRANT SELECT, INSERT, UPDATE
ON TABLE public.user_profiles
TO service_role;

REVOKE DELETE
ON TABLE public.user_profiles
FROM service_role;
