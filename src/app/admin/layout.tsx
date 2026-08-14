import { AppShell } from "@/components/app-shell";
import { requireGM } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const { user } = await requireGM();

  return (
    <AppShell email={user.email} isGM>
      <div className="border-b border-stone-800 bg-stone-900/40">
        <div className="mx-auto max-w-6xl px-6 py-3 text-sm font-medium text-amber-200">
          GM 管理后台
        </div>
      </div>
      {children}
    </AppShell>
  );
}
