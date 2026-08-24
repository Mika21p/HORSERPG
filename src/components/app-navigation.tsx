"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

export type NavItem = { href: string; label: string; marker: string };
export type NavSection = { label: string; items: NavItem[] };

const playerSections: NavSection[] = [
  { label: "概览", items: [{ href: "/", label: "会所首页", marker: "01" }] },
  {
    label: "马房档案",
    items: [
      { href: "/owners", label: "马主名录", marker: "02" },
      { href: "/horses", label: "马匹档案", marker: "03" },
    ],
  },
  {
    label: "交易市场",
    items: [
      { href: "/foal-trade", label: "庭先交易", marker: "04" },
      { href: "/public-auction", label: "公开拍卖", marker: "05" },
    ],
  },
  {
    label: "赛事中心",
    items: [
      { href: "/races", label: "比赛与报名", marker: "06" },
      { href: "/results", label: "比赛结果", marker: "07" },
      { href: "/retirement", label: "退役与奖金", marker: "08" },
    ],
  },
];

const gmSections: NavSection[] = [
  {
    label: "工作台",
    items: [
      { href: "/admin", label: "管理总览", marker: "G1" },
      { href: "/admin/game-state", label: "时间推进", marker: "G2" },
    ],
  },
  {
    label: "赛事",
    items: [
      { href: "/admin/races", label: "报名与赛程", marker: "G3" },
      { href: "/admin/race-results", label: "赛果录入", marker: "G4" },
      { href: "/admin/retirement", label: "退役结算", marker: "G5" },
    ],
  },
  {
    label: "市场与繁育",
    items: [
      { href: "/admin/foal-trade", label: "庭先交易", marker: "G6" },
      { href: "/admin/public-auction", label: "公开拍卖", marker: "G7" },
      { href: "/admin/breeding", label: "繁育管理", marker: "G8" },
    ],
  },
  {
    label: "基础资料",
    items: [
      { href: "/admin/horses", label: "马匹", marker: "G9" },
      { href: "/admin/owners", label: "马主", marker: "G10" },
      { href: "/admin/users", label: "用户", marker: "G11" },
    ],
  },
];

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  if (href === "/admin") return pathname === "/admin";
  return pathname === href || pathname.startsWith(`${href}/`);
}

function NavigationLinks({ isGM, onNavigate }: { isGM: boolean; onNavigate?: () => void }) {
  const pathname = usePathname();
  const isAdminWorkspace = isGM && pathname.startsWith("/admin");
  const sections = isAdminWorkspace ? gmSections : playerSections;

  return (
    <nav aria-label="主导航" className="space-y-7">
      {sections.map((section) => (
        <section key={section.label}>
          <p className="mb-2 px-3 text-[0.68rem] font-bold uppercase tracking-[0.18em] text-[#8d948f]">{section.label}</p>
          <div className="space-y-1">
            {section.items.map((item) => {
              const active = isActive(pathname, item.href);
              return (
                <Link
                  aria-current={active ? "page" : undefined}
                  className={`group flex min-h-11 items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium ${active ? "bg-[#173f35] text-white shadow-[0_8px_20px_rgb(23_63_53/18%)]" : "text-[#4e5952] hover:bg-[#ebe5da] hover:text-[#173f35]"}`}
                  href={item.href}
                  key={item.href}
                  onClick={onNavigate}
                >
                  <span aria-hidden className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-lg border font-mono text-[0.64rem] font-bold ${active ? "border-white/25 bg-white/10 text-[#ead79c]" : "border-[#d8d0c2] bg-[#fffcf6] text-[#7d5b24] group-hover:border-[#b58a3c]"}`}>
                    {item.marker}
                  </span>
                  <span>{item.label}</span>
                </Link>
              );
            })}
          </div>
        </section>
      ))}
    </nav>
  );
}

function WorkspaceSwitch({ isGM, onNavigate }: { isGM: boolean; onNavigate?: () => void }) {
  const pathname = usePathname();
  if (!isGM) return null;
  const adminWorkspace = pathname.startsWith("/admin");
  return (
    <Link className="mb-5 flex min-h-11 items-center justify-between rounded-xl border border-[#d7c393] bg-[#f4ead0] px-3 py-2.5 text-sm font-bold text-[#735421] hover:border-[#b58a3c] hover:bg-[#efe0bc]" href={adminWorkspace ? "/" : "/admin"} onClick={onNavigate}>
      <span>{adminWorkspace ? "切换到玩家视图" : "进入 GM 工作台"}</span>
      <span aria-hidden>↔</span>
    </Link>
  );
}

type AppNavigationProps = {
  accountActions: React.ReactNode;
  email: string | undefined;
  gameTime: string;
  isGM: boolean;
};

export function AppNavigation({ accountActions, email, gameTime, isGM }: AppNavigationProps) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();
  const isAdminWorkspace = isGM && pathname.startsWith("/admin");

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape") setOpen(false); };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [open]);

  return (
    <>
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-[248px] flex-col border-r border-[#d8d0c2] bg-[#fffcf6]/95 px-4 pb-5 pt-6 shadow-[12px_0_40px_rgb(57_47_31/5%)] backdrop-blur lg:flex">
        <Link className="group px-3" href={isAdminWorkspace ? "/admin" : "/"}>
          <span className="block text-[0.65rem] font-bold tracking-[0.28em] text-[#9a7131]">WINNING POST</span>
          <span className="display-title mt-1 block text-2xl font-semibold text-[#173f35]">HorseRPG</span>
          <span className="mt-1 block text-xs text-[#7a837d]">赛马跑团管理会所</span>
        </Link>
        <div className="my-5 h-px bg-gradient-to-r from-transparent via-[#b58a3c]/55 to-transparent" />
        <div className="min-h-0 flex-1 overflow-y-auto pr-1"><WorkspaceSwitch isGM={isGM} /><NavigationLinks isGM={isGM} /></div>
        <div className="mt-5 border-t border-[#d8d0c2] px-3 pt-4">
          <p className="truncate text-xs font-medium text-[#4e5952]">{email}</p>
          <p className="mt-1 text-[0.68rem] uppercase tracking-[0.14em] text-[#8d948f]">{isGM ? "Game Master" : "Player"}</p>
          <div className="mt-3">{accountActions}</div>
        </div>
      </aside>

      <header className="sticky top-0 z-20 flex min-h-16 items-center justify-between gap-3 border-b border-[#d8d0c2] bg-[#fffcf6]/92 px-4 backdrop-blur sm:px-6 lg:ml-[248px]">
        <div className="flex min-w-0 items-center gap-3">
          <button aria-expanded={open} aria-label="打开主导航" className="flex h-11 w-11 shrink-0 flex-col items-center justify-center gap-1.5 rounded-xl border border-[#d8d0c2] bg-white text-[#173f35] hover:border-[#b58a3c] lg:hidden" onClick={() => setOpen(true)} type="button">
            <span className="h-0.5 w-5 bg-current" /><span className="h-0.5 w-5 bg-current" /><span className="h-0.5 w-5 bg-current" />
          </button>
          <Link className="display-title truncate text-lg font-semibold text-[#173f35] lg:hidden" href="/">HorseRPG</Link>
          <div className="hidden min-w-0 sm:block lg:ml-1">
            <p className="text-[0.65rem] font-bold uppercase tracking-[0.17em] text-[#929892]">当前 Winning Post 时间</p>
            <p className="truncate text-sm font-semibold text-[#35413a]">{gameTime}{isGM && <Link className="ml-3 text-xs font-bold text-[#8a6328] hover:text-[#173f35]" href="/admin/game-state">管理时间</Link>}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <span className="rounded-full border border-[#d7c393] bg-[#f4ead0] px-3 py-1.5 text-xs font-bold text-[#735421]">{isGM ? "GM" : "PLAYER"}</span>
          <span className="hidden max-w-56 truncate text-xs text-[#68736c] md:block">{email}</span>
          <div className="lg:hidden">{accountActions}</div>
        </div>
      </header>

      {open && (
        <div className="fixed inset-0 z-50 lg:hidden">
          <button aria-label="关闭主导航" className="absolute inset-0 bg-[#0f211c]/45 backdrop-blur-sm" onClick={() => setOpen(false)} type="button" />
          <aside className="absolute inset-y-0 left-0 flex w-[min(88vw,340px)] flex-col bg-[#fffcf6] p-5 shadow-2xl">
            <div className="flex items-start justify-between gap-4">
              <Link href={isAdminWorkspace ? "/admin" : "/"} onClick={() => setOpen(false)}>
                <span className="block text-[0.62rem] font-bold tracking-[0.26em] text-[#9a7131]">WINNING POST</span>
                <span className="display-title mt-1 block text-2xl font-semibold text-[#173f35]">HorseRPG</span>
              </Link>
              <button aria-label="关闭主导航" className="flex h-11 w-11 items-center justify-center rounded-xl border border-[#d8d0c2] text-2xl leading-none text-[#173f35]" onClick={() => setOpen(false)} type="button">×</button>
            </div>
            <div className="my-5 h-px bg-[#d8d0c2]" />
            <div className="min-h-0 flex-1 overflow-y-auto"><WorkspaceSwitch isGM={isGM} onNavigate={() => setOpen(false)} /><NavigationLinks isGM={isGM} onNavigate={() => setOpen(false)} /></div>
            <div className="mt-5 border-t border-[#d8d0c2] pt-4">
              <p className="truncate text-xs font-medium text-[#4e5952]">{email}</p>
              <p className="mt-1 text-xs text-[#7a837d]">{gameTime}</p>
            </div>
          </aside>
        </div>
      )}
    </>
  );
}
