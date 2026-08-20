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
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-3 px-4 py-4 sm:gap-5 sm:px-6">
          <Link className="font-semibold tracking-[0.2em] text-amber-300" href="/">
            HORSE RPG
          </Link>
          <nav className="order-3 flex basis-full flex-wrap gap-x-4 gap-y-2 text-sm text-stone-300 sm:order-none sm:basis-auto sm:flex-1">
            <Link className="hover:text-amber-200" href="/owners">
              Owners
            </Link>
            <Link className="hover:text-amber-200" href="/horses">
              Horses
            </Link>
            <Link className="hover:text-amber-200" href="/foal-trade">
              庭先取引
            </Link>
            <Link className="hover:text-amber-200" href="/public-auction">
              公开拍卖
            </Link>
            <Link className="hover:text-amber-200" href="/races">
              比赛 / Race
            </Link>
            <Link className="hover:text-amber-200" href="/results">
              赛果
            </Link>
            {isGM && (
              <>
                <Link className="hover:text-amber-200" href="/admin/race-results">
                  赛果管理
                </Link>
                <Link className="hover:text-amber-200" href="/admin">
                  GM 后台
                </Link>
              </>
            )}
          </nav>
          <div className="ml-auto flex items-center gap-3 text-xs text-stone-400 sm:ml-0">
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
