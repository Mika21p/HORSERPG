import { AppShell } from "@/components/app-shell";
import { requireGM } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { user } = await requireGM();

  return (
    <AppShell email={user.email} isGM>
      {children}
    </AppShell>
  );
}
