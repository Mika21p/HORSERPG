import {
  advanceGameStateOneWeek,
  correctGameState,
  initializeGameState,
} from "@/app/admin/actions";
import { ActionForm } from "@/components/action-form";
import { DangerZone, GMPageHeader, GMSectionNav } from "@/components/gm-admin-ui";
import { Notice } from "@/components/notice";
import { StatusBadge } from "@/components/ui/primitives";
import { requireGM } from "@/lib/auth/session";
import { formatDateTime, formatWpTime } from "@/lib/format";
import { nextWpTime, wpTimeOrder, type WpTime } from "@/lib/wp-time";

type PageProps = { searchParams: Promise<{ notice?: string }> };

const auditLabels: Record<string, string> = {
  GAME_STATE_INITIALIZED: "初始化时间",
  GAME_STATE_ADVANCED: "推进一周",
  GAME_STATE_CORRECTED: "人工纠正",
};

function WpFields({ defaults }: { defaults: WpTime }) {
  return (
    <div className="grid gap-4 sm:grid-cols-3">
      <label className="admin-label" htmlFor="current_wp_year">WP 年<input className="admin-input" defaultValue={defaults.year} id="current_wp_year" min="1" name="current_wp_year" required type="number" /></label>
      <label className="admin-label" htmlFor="current_wp_month">月<input className="admin-input" defaultValue={defaults.month} id="current_wp_month" max="12" min="1" name="current_wp_month" required type="number" /></label>
      <label className="admin-label" htmlFor="current_wp_week">周<input className="admin-input" defaultValue={defaults.week} id="current_wp_week" max="5" min="1" name="current_wp_week" required type="number" /></label>
    </div>
  );
}

export default async function GameStatePage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const [{ data: gameState }, { data: auditLogs }] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week, updated_at").maybeSingle(),
    supabase.from("audit_logs").select("id, action, before_data, after_data, reason, created_at").eq("entity_type", "game_state").eq("entity_id", "current").order("created_at", { ascending: false }).limit(10),
  ]);

  let missingResultCount = 0;
  let stalePendingCount = 0;
  let recoveringInjuryCount = 0;
  let current: WpTime | null = null;
  let next: WpTime | null = null;

  if (gameState) {
    current = { year: gameState.current_wp_year, month: gameState.current_wp_month, week: gameState.current_wp_week };
    next = nextWpTime(current);
    const [{ data: entries }, { data: pendingRequests }, { count: injuryCount }] = await Promise.all([
      supabase.from("confirmed_race_entries").select("id").eq("wp_year", current.year).eq("wp_month", current.month).eq("wp_week", current.week),
      supabase.from("race_entry_requests").select("requested_wp_year, requested_wp_month, requested_wp_week").eq("status", "PENDING"),
      supabase.from("injuries").select("id", { count: "exact", head: true }).eq("status", "ACTIVE").eq("wp_end_year", current.year).eq("wp_end_month", current.month).eq("wp_end_week", current.week),
    ]);
    const entryIds = (entries ?? []).map((entry) => entry.id);
    const { data: results } = entryIds.length
      ? await supabase.from("race_results").select("confirmed_race_entry_id").eq("status", "CONFIRMED").in("confirmed_race_entry_id", entryIds)
      : { data: [] };
    const completed = new Set((results ?? []).map((result) => result.confirmed_race_entry_id));
    missingResultCount = entryIds.filter((id) => !completed.has(id)).length;
    stalePendingCount = (pendingRequests ?? []).filter((request) => wpTimeOrder({
      year: request.requested_wp_year,
      month: request.requested_wp_month,
      week: request.requested_wp_week,
    }) < wpTimeOrder(next as WpTime)).length;
    recoveringInjuryCount = injuryCount ?? 0;
  }

  return (
    <main className="page-wrap">
      <GMPageHeader
        action={<StatusBadge tone={gameState ? "warning" : "neutral"}>{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "尚未初始化"}</StatusBadge>}
        description="时间推进只改变 Winning Post 时钟；赛程、伤病、报名、奖金与退役状态均由 GM 在各自工作台独立裁定。"
        eyebrow="CONTROLLED TIMEKEEPING"
        title="Winning Post 时间推进"
      />
      <Notice message={notice} />

      {gameState && current && next ? (
        <>
          <GMSectionNav items={[
            { href: "#progression", label: "安全推进" },
            { count: missingResultCount + stalePendingCount + recoveringInjuryCount, href: "#preflight", label: "影响预检" },
            { href: "#history", label: "操作记录" },
            { href: "#correction", label: "高级纠正" },
          ]} />

          <section className="scroll-mt-32 mt-7 overflow-hidden rounded-3xl bg-[#173f35] p-6 text-white shadow-[0_18px_44px_rgb(23_63_53/18%)] sm:p-8" id="progression">
            <p className="text-xs font-bold uppercase tracking-[0.2em] text-[#d6b66a]">NEXT CONTROLLED STEP</p>
            <div className="mt-5 grid items-center gap-5 md:grid-cols-[1fr_auto_1fr]">
              <div><p className="text-xs text-white/60">当前时间</p><p className="display-title mt-2 text-2xl font-semibold">{formatWpTime(current.year, current.month, current.week)}</p></div>
              <span aria-hidden className="text-3xl text-[#d6b66a]">→</span>
              <div><p className="text-xs text-white/60">下一时间</p><p className="display-title mt-2 text-2xl font-semibold text-[#f1dfaa]">{formatWpTime(next.year, next.month, next.week)}</p></div>
            </div>
            <div className="mt-7 border-t border-white/15 pt-6">
              <ActionForm action={advanceGameStateOneWeek} confirmation={`确认将时间从 ${formatWpTime(current.year, current.month, current.week)} 推进到 ${formatWpTime(next.year, next.month, next.week)}？此操作会写入审计记录。`} pendingLabel="正在推进…" submitLabel="推进到下一周">
                <input name="expected_wp_year" type="hidden" value={current.year} />
                <input name="expected_wp_month" type="hidden" value={current.month} />
                <input name="expected_wp_week" type="hidden" value={current.week} />
              </ActionForm>
            </div>
          </section>

          <section className="scroll-mt-32 mt-9" id="preflight">
            <div><p className="page-eyebrow">ADVISORY PREVIEW</p><h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">推进影响预检</h2><p className="mt-2 text-sm leading-6 text-[#68736c]">以下项目仅作提醒，不会阻止推进，也不会被自动处理。</p></div>
            <div className="mt-5 grid gap-4 lg:grid-cols-3">
              {[
                [missingResultCount, "本周待录有效赛果", "已确认在当前周参赛，但尚无有效赛果。", "/admin/race-results"],
                [stalePendingCount, "将早于新时间的待审核报名", "推进后这些玩家意图仍保持待审核，需 GM 另行处理。", "/admin/races#pending"],
                [recoveringInjuryCount, "本周结束的伤病", "这些马匹从下一周起可能恢复参赛资格，状态不会自动修改。", "/admin/horses"],
              ].map(([count, label, description, href]) => (
                <a className="rounded-2xl border border-[#d8d0c2] bg-[#fffcf6] p-5 hover:border-[#b58a3c]" href={String(href)} key={String(label)}>
                  <div className="flex items-start justify-between gap-4"><div><h3 className="font-bold text-[#26342c]">{label}</h3><p className="mt-2 text-sm leading-6 text-[#68736c]">{description}</p></div><span className="font-mono text-3xl font-semibold text-[#735421]">{count}</span></div>
                </a>
              ))}
            </div>
          </section>

          <section className="scroll-mt-32 mt-10 border-t border-[#d8d0c2] pt-9" id="history">
            <details className="rounded-2xl border border-[#d8d0c2] bg-[#fffcf6] p-5">
              <summary className="cursor-pointer font-semibold text-[#173f35]">最近时间操作记录</summary>
              <div className="mt-5 divide-y divide-[#e4ddd2]">
                {(auditLogs ?? []).map((log) => {
                  const before = log.before_data as { current_wp_year?: number; current_wp_month?: number; current_wp_week?: number } | null;
                  const after = log.after_data as { current_wp_year?: number; current_wp_month?: number; current_wp_week?: number } | null;
                  return <article className="py-4 first:pt-0" key={log.id}><div className="flex flex-wrap items-center justify-between gap-2"><p className="font-semibold text-[#26342c]">{auditLabels[log.action] ?? log.action}</p><time className="text-xs text-[#7a837d]">{formatDateTime(log.created_at)}</time></div><p className="mt-2 text-sm text-[#68736c]">{before ? formatWpTime(before.current_wp_year, before.current_wp_month, before.current_wp_week) : "未设置"} → {after ? formatWpTime(after.current_wp_year, after.current_wp_month, after.current_wp_week) : "—"}</p>{log.reason && <p className="mt-1 text-xs text-[#76514f]">原因：{log.reason}</p>}</article>;
                })}
                {!auditLogs?.length && <p className="py-4 text-sm text-[#7a837d]">暂无审计记录。</p>}
              </div>
            </details>
          </section>

          <div className="scroll-mt-32 mt-10" id="correction">
            <DangerZone description="仅用于修正录入错误。可向前或向后调整，但必须填写原因并输入严格确认文本；数据库仍会校验页面所见旧时间，避免并发覆盖。" title="高级时间纠正">
              <ActionForm action={correctGameState} className="space-y-5" confirmation="确认执行人工时间纠正？这不是正常推进流程，前后时间和原因都会永久写入审计记录。" pendingLabel="正在纠正…" submitLabel="纠正 Winning Post 时间" variant="danger">
                <input name="expected_wp_year" type="hidden" value={current.year} />
                <input name="expected_wp_month" type="hidden" value={current.month} />
                <input name="expected_wp_week" type="hidden" value={current.week} />
                <WpFields defaults={current} />
                <label className="admin-label" htmlFor="reason">纠正原因<textarea className="admin-input min-h-24" id="reason" name="reason" placeholder="说明为何需要偏离正常的一周推进流程" required /></label>
                <label className="admin-label" htmlFor="confirmation">严格确认文本<input autoComplete="off" className="admin-input font-mono" id="confirmation" name="confirmation" pattern="CORRECT WP TIME" placeholder="CORRECT WP TIME" required /></label>
              </ActionForm>
            </DangerZone>
          </div>
        </>
      ) : (
        <section className="mt-7 rounded-2xl border border-[#d8d0c2] bg-[#fffcf6] p-6 sm:p-8">
          <p className="page-eyebrow">FIRST SETUP</p><h2 className="display-title mt-2 text-2xl font-semibold text-[#173f35]">初始化游戏时间</h2><p className="mt-2 text-sm leading-6 text-[#68736c]">此操作只在尚无时间记录时可用，并会写入第一条时间审计记录。</p>
          <ActionForm action={initializeGameState} className="mt-6 space-y-5" confirmation="确认以此时间初始化 Winning Post？初始化后，常规操作每次只能推进一周。" pendingLabel="正在初始化…" submitLabel="初始化当前时间">
            <WpFields defaults={{ year: 1, month: 1, week: 1 }} />
          </ActionForm>
        </section>
      )}
    </main>
  );
}
