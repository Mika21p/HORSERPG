import Link from "next/link";

import { GMPageHeader, GMTaskSummary } from "@/components/gm-admin-ui";
import { StatusBadge } from "@/components/ui/primitives";
import { requireGM } from "@/lib/auth/session";
import { formatWpTime } from "@/lib/format";
import { nextWpTime, wpTimeOrder } from "@/lib/wp-time";

const operations = [
  ["庭先交易", "/admin/foal-trade", "管理届次、Lot、询问、秘密报价与结算", "G6"],
  ["公开拍卖", "/admin/public-auction", "主持年末拍卖、公开竞价与受控回滚", "G7"],
  ["报名与赛程", "/admin/races", "审核报名、直接排程并维护比赛目录", "G3"],
  ["赛果录入", "/admin/race-results", "录入实际比赛、赛果、赏金与修正", "G4"],
  ["退役结算", "/admin/retirement", "审核退役申请并释放待结算奖金", "G5"],
  ["繁育与幼驹", "/admin/breeding", "管理繁育候选、血统资料与出生幼驹", "G8"],
] as const;

const records = [
  ["马匹", "/admin/horses", "维护 Horse、生命周期与 Horse Factors", "G9"],
  ["马主", "/admin/owners", "创建与维护 Owner 公开基础资料", "G10"],
  ["用户", "/admin/users", "创建 PLAYER 并绑定可用 Owner", "G11"],
] as const;

function AdminCard({ entry, emphasis = false }: { entry: readonly [string, string, string, string]; emphasis?: boolean }) {
  const [title, href, description, marker] = entry;
  return (
    <Link className={`group rounded-2xl border p-5 hover:-translate-y-0.5 hover:border-[#b58a3c] ${emphasis ? "border-[#cfc2a8] bg-[#fffcf6] shadow-[0_12px_32px_rgb(57_47_31/7%)]" : "border-[#d8d0c2] bg-[#f8f4ed]"}`} href={href}>
      <div className="flex items-start gap-4">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-[#d7c393] bg-[#f4ead0] font-mono text-[0.68rem] font-bold text-[#735421]">{marker}</span>
        <div><h3 className="display-title text-xl font-semibold text-[#173f35]">{title}</h3><p className="mt-2 text-sm leading-6 text-[#68736c]">{description}</p></div>
      </div>
    </Link>
  );
}

export default async function AdminHomePage() {
  const { supabase } = await requireGM();
  const [
    { data: gameState },
    { count: pendingRaceRequests },
    { count: pendingRetirements },
    { count: unansweredInquiries },
    { count: unsettledFoalSessions },
    { count: closedAuctionLots },
  ] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("race_entry_requests").select("id", { count: "exact", head: true }).eq("status", "PENDING"),
    supabase.from("horse_retirement_requests").select("id", { count: "exact", head: true }).eq("status", "PENDING"),
    supabase.from("foal_trade_inquiries").select("id", { count: "exact", head: true }).eq("status", "REQUESTED"),
    supabase.from("foal_trade_sessions").select("id", { count: "exact", head: true }).in("status", ["CLOSED", "REVIEWING"]),
    supabase.from("public_auction_lots").select("id", { count: "exact", head: true }).eq("status", "CLOSED"),
  ]);

  let missingResults = 0;
  if (gameState) {
    const { data: entries } = await supabase.from("confirmed_race_entries").select("id, wp_year, wp_month, wp_week");
    const currentOrder = wpTimeOrder({ year: gameState.current_wp_year, month: gameState.current_wp_month, week: gameState.current_wp_week });
    const entryIds = (entries ?? []).filter((entry) => wpTimeOrder({ year: entry.wp_year, month: entry.wp_month, week: entry.wp_week }) <= currentOrder).map((entry) => entry.id);
    const { data: results } = entryIds.length
      ? await supabase.from("race_results").select("confirmed_race_entry_id").eq("status", "CONFIRMED").in("confirmed_race_entry_id", entryIds)
      : { data: [] };
    const completed = new Set((results ?? []).map((result) => result.confirmed_race_entry_id));
    missingResults = entryIds.filter((id) => !completed.has(id)).length;
  }

  const next = gameState ? nextWpTime({ year: gameState.current_wp_year, month: gameState.current_wp_month, week: gameState.current_wp_week }) : null;

  return (
    <main className="page-wrap">
      <GMPageHeader action={<StatusBadge tone="warning">GM 专用工作区</StatusBadge>} description="先查看时间与待办，再进入对应业务域裁定。统计均来自现有业务记录，不会自动改变任何流程状态。" eyebrow="GAME MASTER OFFICE" title="GM 管理总览" />

      <section className="mt-7 overflow-hidden rounded-3xl bg-[#173f35] p-6 text-white shadow-[0_18px_44px_rgb(23_63_53/16%)] sm:p-8">
        <div className="grid items-end gap-6 lg:grid-cols-[1fr_auto]">
          <div>
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-[#d6b66a]">WINNING POST CLOCK</p>
            {gameState && next ? <><p className="display-title mt-3 text-3xl font-semibold">{formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week)}</p><p className="mt-2 text-sm text-white/65">下一周预览：{formatWpTime(next.year, next.month, next.week)}</p></> : <><p className="display-title mt-3 text-3xl font-semibold">尚未初始化</p><p className="mt-2 text-sm text-white/65">请先设置首个 Winning Post 时间。</p></>}
          </div>
          <Link className="inline-flex min-h-11 items-center justify-center rounded-xl bg-[#d6b66a] px-5 py-3 text-sm font-bold text-[#173f35] hover:bg-[#e6ca84]" href="/admin/game-state">{gameState ? "检查并推进" : "初始化时间"}</Link>
        </div>
      </section>

      <section className="mt-9">
        <p className="page-eyebrow">LIVE TASK SUMMARY</p><h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">需要 GM 处理</h2><p className="mt-2 text-sm text-[#68736c]">数字实时汇总自现有表；为 0 时仍保留入口，便于确认空状态。</p>
        <div className="mt-5"><GMTaskSummary items={[
          { count: pendingRaceRequests ?? 0, description: "玩家提交、尚未确认或拒绝", href: "/admin/races#pending", label: "待审核报名", tone: "warning" },
          { count: missingResults, description: "本周已确认参赛但尚无有效赛果", href: "/admin/race-results", label: "待录赛果", tone: "warning" },
          { count: pendingRetirements ?? 0, description: "等待退役裁定与奖金释放", href: "/admin/retirement#pending", label: "待处理退役", tone: "warning" },
          { count: unansweredInquiries ?? 0, description: "庭先询问尚未填写 GM 回答", href: "/admin/foal-trade", label: "未回答庭先询问", tone: "neutral" },
          { count: unsettledFoalSessions ?? 0, description: "已关闭或正在审核的庭先届次", href: "/admin/foal-trade", label: "待结算庭先届次", tone: "neutral" },
          { count: closedAuctionLots ?? 0, description: "竞价已关闭、尚待主持确认", href: "/admin/public-auction", label: "拍卖 Lot 待确认", tone: "neutral" },
        ]} /></div>
      </section>

      <section className="mt-11 border-t border-[#d8d0c2] pt-9">
        <p className="page-eyebrow">OPERATIONS</p><h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">业务裁定与结算</h2><p className="mt-2 text-sm text-[#68736c]">涉及玩家意图、比赛事实、交易结果和资金变化的主要工作台。</p>
        <div className="mt-5 grid gap-4 md:grid-cols-2 2xl:grid-cols-3">{operations.map((entry) => <AdminCard emphasis entry={entry} key={entry[1]} />)}</div>
      </section>
      <section className="mt-11 border-t border-[#d8d0c2] pt-9">
        <p className="page-eyebrow">RECORDS</p><h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">基础资料</h2><p className="mt-2 text-sm text-[#68736c]">维护核心档案与账号归属；低频资料入口与流程待办分开陈列。</p>
        <div className="mt-5 grid gap-4 md:grid-cols-2 2xl:grid-cols-3">{records.map((entry) => <AdminCard entry={entry} key={entry[1]} />)}</div>
      </section>
    </main>
  );
}
