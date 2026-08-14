import Link from "next/link";

import { signOut } from "@/app/actions/auth";

type AppShellProps = {
  children: React.ReactNode;
  email: string | undefined;
  isGM: boolean;
};

export function AppShell({ children, email, isGM }: AppShellProps) {
  return (
    <div className="min-h-screen bg-stone-950 text-stone-100">
      <header className="border-b border-stone-800 bg-stone-900/80">
        <div className="mx-auto flex max-w-6xl items-center gap-5 px-6 py-4">
          <Link className="font-semibold tracking-[0.2em] text-amber-300" href="/">
            HORSE RPG
          </Link>
          <nav className="flex flex-1 gap-4 text-sm text-stone-300">
            <Link className="hover:text-amber-200" href="/owners">
              Owners
            </Link>
            <Link className="hover:text-amber-200" href="/horses">
              Horses
            </Link>
            {isGM && (
              <Link className="hover:text-amber-200" href="/admin">
                GM 后台
              </Link>
            )}
          </nav>
          <div className="flex items-center gap-3 text-xs text-stone-400">
            <span className="hidden sm:inline">{email}</span>
            <form action={signOut}>
              <button className="rounded-md border border-stone-700 px-3 py-1.5 hover:border-amber-300 hover:text-amber-200">
                退出
              </button>
            </form>
          </div>
        </div>
      </header>
      {children}
    </div>
  );
}
