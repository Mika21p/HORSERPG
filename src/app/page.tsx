import Link from "next/link";

import { AppShell } from "@/components/app-shell";
import { PageHeader, StatusBadge, Surface } from "@/components/ui/primitives";
import { requireUser } from "@/lib/auth/session";

export const dynamic = "force-dynamic";

const playerEntries = [
  ["马匹档案", "/horses", "查看公开马匹、血统、战绩与健康记录", "03"],
  ["马主名录", "/owners", "浏览跑团中的公开 Owner 档案", "02"],
  ["比赛与报名", "/races", "提交比赛意向并追踪 GM 最终确认", "06"],
  ["公开拍卖", "/public-auction", "进入年末拍卖会与实时竞价现场", "05"],
] as const;

const gmEntries = [
  ["管理总览", "/admin", "进入 GM 业务工作台与资料维护入口", "G1"],
  ["赛果管理", "/admin/race-results", "录入、确认并修正 Winning Post 赛果", "G9"],
  ["繁育管理", "/admin/breeding", "管理繁育候选与新生幼驹档案", "G10"],
  ["拍卖主持", "/admin/public-auction", "主持 Lot 展示、竞价与最终结算", "G7"],
] as const;

export default async function Home() {
  const { supabase, user, profile } = await requireUser();
  const { data: gameState } = await supabase
    .from("game_state")
    .select("current_wp_year, current_wp_month, current_wp_week")
    .maybeSingle();
  const isGM = profile?.role === "GM";
  const entries = isGM ? gmEntries : playerEntries;
  const time = gameState
    ? `${gameState.current_wp_year}年 ${String(gameState.current_wp_month).padStart(2, "0")}月 第${gameState.current_wp_week}周`
    : "当前游戏时间尚未由 GM 设置";

  return (
    <AppShell email={user.email} isGM={isGM}>
      <main className="page-wrap">
        <PageHeader
          action={<StatusBadge tone={isGM ? "warning" : "success"}>{isGM ? "GM 会话" : "PLAYER 会话"}</StatusBadge>}
          description={isGM ? "集中处理需要裁定的流程，并维护跑团的权威记录。" : "从马房档案、交易市场到比赛日程，查看你在本周需要关注的一切。"}
          eyebrow="HORSE RACING CLUB"
          title={isGM ? "GM 会所总览" : "欢迎回到马房"}
        />

        <div className="mt-8 grid gap-6 xl:grid-cols-[minmax(0,1.25fr)_minmax(20rem,0.75fr)]">
          <Surface className="relative overflow-hidden bg-[#173f35] text-white">
            <div className="absolute -right-24 -top-20 h-72 w-72 rounded-full border border-[#d6b66a]/25" />
            <div className="absolute -right-10 -top-4 h-48 w-48 rounded-full border border-[#d6b66a]/20" />
            <div className="relative">
              <p className="text-xs font-bold uppercase tracking-[0.2em] text-[#d6b66a]">CURRENT SEASON</p>
              <p className="display-title mt-4 text-3xl font-semibold sm:text-4xl">{time}</p>
              <p className="mt-4 max-w-xl text-sm leading-7 text-[#d5ded9]">所有报名、拍卖截单、伤病周期与退役判断，均以这一 Winning Post 时间为共同基准。</p>
            </div>
          </Surface>

          <Surface>
            <p className="text-xs font-bold uppercase tracking-[0.18em] text-[#9a7131]">CLUB PRINCIPLE</p>
            <h2 className="display-title mt-3 text-2xl font-semibold text-[#173f35]">玩家提出意图，GM 作出裁定</h2>
            <p className="mt-3 text-sm leading-7 text-[#68736c]">网站保存公开资料、业务进度与最终事实；Winning Post 与 GM 始终是跑团规则的权威来源。</p>
          </Surface>
        </div>

        <section className="mt-10">
          <div className="flex items-end justify-between gap-4">
            <div>
              <p className="page-eyebrow">QUICK ACCESS</p>
              <h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">常用入口</h2>
            </div>
            <p className="hidden text-sm text-[#737c76] sm:block">按当前身份显示</p>
          </div>
          <div className="mt-5 grid gap-4 sm:grid-cols-2">
            {entries.map(([title, href, description, marker]) => (
              <Link className="group rounded-2xl border border-[#d8d0c2] bg-[#fffcf6] p-5 shadow-[0_10px_30px_rgb(57_47_31/5%)] hover:-translate-y-0.5 hover:border-[#b58a3c] hover:shadow-[0_16px_34px_rgb(57_47_31/9%)]" href={href} key={href}>
                <div className="flex items-start gap-4">
                  <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#d7c393] bg-[#f4ead0] font-mono text-xs font-bold text-[#735421]">{marker}</span>
                  <div>
                    <h3 className="display-title text-xl font-semibold text-[#173f35] group-hover:text-[#245649]">{title}</h3>
                    <p className="mt-2 text-sm leading-6 text-[#68736c]">{description}</p>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </section>
      </main>
    </AppShell>
  );
}
