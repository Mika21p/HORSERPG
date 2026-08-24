import { ActionForm } from "@/components/action-form";
import { Notice } from "@/components/notice";
import { RaceScheduleForm, type RaceHorseOption } from "@/components/race-schedule-form";
import {
  confirmRaceEntryRequest,
  createDirectRaceEntry,
  createRaceCatalog,
  rejectRaceEntryRequest,
  updateRaceCatalog,
} from "@/app/admin/races/actions";
import { requireGM } from "@/lib/auth/session";
import {
  formatDateTime,
  formatRaceEntryRequestStatus,
  formatRaceKind,
  formatWpTime,
} from "@/lib/format";

type PageProps = { searchParams: Promise<{ notice?: string }> };

type RaceIdentity = {
  race_kind: string;
  race_catalog_id: string | null;
  race_label: string | null;
};

function horseName(horse: { translated_name: string | null; foal_name: string } | undefined) {
  return horse?.translated_name || horse?.foal_name || "Horse";
}

function raceName(entry: RaceIdentity, catalogNames: Map<string, string>) {
  if (entry.race_kind === "CATALOG") return entry.race_catalog_id ? catalogNames.get(entry.race_catalog_id) ?? "固定比赛" : "固定比赛";
  return entry.race_label || formatRaceKind(entry.race_kind);
}

function requestedRaceName(entry: { requested_race_kind: string; requested_race_catalog_id: string | null; requested_race_label: string | null }, catalogNames: Map<string, string>) {
  return raceName({
    race_kind: entry.requested_race_kind,
    race_catalog_id: entry.requested_race_catalog_id,
    race_label: entry.requested_race_label,
  }, catalogNames);
}

export const dynamic = "force-dynamic";

export default async function AdminRacesPage({ searchParams }: PageProps) {
  const [{ supabase }, { notice }] = await Promise.all([requireGM(), searchParams]);
  const [{ data: gameState, error: gameStateError }, { data: catalogs, error: catalogError }, { data: requests, error: requestError }, { data: entries, error: entryError }, { data: horses, error: horseError }, { data: owners, error: ownerError }, { data: injuries, error: injuryError }] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("race_catalog").select("id, name, grade, default_wp_month, default_wp_week, is_active, created_at, updated_at").order("name"),
    supabase.from("race_entry_requests").select("id, horse_id, owner_id, requested_wp_year, requested_wp_month, requested_wp_week, requested_race_kind, requested_race_catalog_id, requested_race_label, requested_jockey, requested_running_style, player_note, status, rejection_reason, created_at, reviewed_at").order("created_at", { ascending: false }),
    supabase.from("confirmed_race_entries").select("id, request_id, horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_label, jockey, running_style, gm_note, confirmed_at").order("wp_year").order("wp_month").order("wp_week").order("confirmed_at"),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, owner_id, life_stage, current_jockey_name").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
    supabase.from("injuries_public").select("horse_id, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week").eq("status", "ACTIVE"),
  ]);

  const dataError = gameStateError || catalogError || requestError || entryError || horseError || ownerError || injuryError;
  const catalogNames = new Map((catalogs ?? []).map((catalog) => [catalog.id, catalog.name]));
  const horsesById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const requestsById = new Map((requests ?? []).map((request) => [request.id, request]));
  const injuriesByHorseId = new Map<string, NonNullable<typeof injuries>>();
  for (const injury of injuries ?? []) {
    injuriesByHorseId.set(injury.horse_id, [...(injuriesByHorseId.get(injury.horse_id) ?? []), injury]);
  }
  const horseOptions: RaceHorseOption[] = (horses ?? []).map((horse) => ({ ...horse, injuries: injuriesByHorseId.get(horse.id) ?? [] }));
  const activeCatalogs = (catalogs ?? []).filter((catalog) => catalog.is_active);
  const pendingRequests = (requests ?? []).filter((request) => request.status === "PENDING");

  return (
    <main className="mx-auto w-full max-w-7xl px-6 py-10">
      <section className="flex flex-col gap-5 border-b border-stone-800 pb-7 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">GM · RACE MANAGEMENT</p>
          <h1 className="mt-3 text-3xl font-semibold tracking-tight">比赛管理</h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-stone-400">审核 PLAYER 报名、直接安排权威赛程，并维护可选固定比赛目录。所有确认、拒绝和直接排程均调用数据库受控 RPC。</p>
        </div>
        <div className="rounded-xl border border-amber-300/30 bg-amber-300/5 px-5 py-4 text-sm"><p className="text-stone-500">当前 Winning Post 时间</p><p className="mt-1 font-semibold text-amber-100">{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "尚未初始化"}</p></div>
      </section>

      <Notice message={notice} />
      {dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分比赛管理数据暂时无法读取。请刷新页面；不会显示数据库内部错误。</p>}

      <section className="mt-8">
        <div className="flex items-end justify-between gap-4"><div><h2 className="text-2xl font-semibold text-amber-200">待审核报名</h2><p className="mt-2 text-sm text-stone-400">PLAYER 原始请求永远只读；GM 可独立编辑最终时间、比赛、骑手、跑法与内部 Note。</p></div><span className="font-mono text-sm text-stone-500">{pendingRequests.length} 条</span></div>
        <div className="mt-5 space-y-6">
          {pendingRequests.map((request) => {
            const horse = horsesById.get(request.horse_id);
            const confirm = confirmRaceEntryRequest.bind(null, request.id);
            const reject = rejectRaceEntryRequest.bind(null, request.id);
            const activeInjuries = injuriesByHorseId.get(request.horse_id) ?? [];
            return (
              <article className="rounded-xl border border-stone-800 bg-stone-900 p-6" key={request.id}>
                <div className="flex flex-col gap-3 border-b border-stone-800 pb-5 sm:flex-row sm:items-start sm:justify-between"><div><p className="font-semibold text-stone-100">{horseName(horse)} <span className="font-mono text-sm text-stone-500">#{horse?.horse_number ?? "—"}</span></p><p className="mt-1 text-sm text-stone-400">Owner：{ownerNames.get(request.owner_id) ?? "Owner"} · 提交于 {formatDateTime(request.created_at)}</p></div><span className="rounded-full border border-amber-300/40 bg-amber-300/10 px-3 py-1 text-xs font-semibold text-amber-100">{formatRaceEntryRequestStatus(request.status)}</span></div>
                <div className="mt-6 grid gap-6 xl:grid-cols-2">
                  <section className="rounded-xl border border-stone-800 bg-stone-950/60 p-5"><p className="text-xs font-semibold tracking-[0.16em] text-stone-500">PLAYER 原始请求 · 只读</p><p className="mt-4 text-lg font-semibold text-stone-100">{formatWpTime(request.requested_wp_year, request.requested_wp_month, request.requested_wp_week)}</p><p className="mt-2 font-medium text-amber-100">{requestedRaceName(request, catalogNames)}</p><dl className="mt-5 grid gap-3 text-sm"><div><dt className="text-stone-500">希望骑手</dt><dd className="mt-1 text-stone-200">{request.requested_jockey || "未指定"}</dd></div><div><dt className="text-stone-500">希望跑法</dt><dd className="mt-1 text-stone-200">{request.requested_running_style || "未指定"}</dd></div><div><dt className="text-stone-500">PLAYER 备注</dt><dd className="mt-1 whitespace-pre-wrap leading-6 text-stone-200">{request.player_note || "—"}</dd></div></dl>{activeInjuries.length > 0 && <div className="mt-5 rounded-lg border border-red-400/35 bg-red-400/5 p-3 text-sm leading-6 text-red-100"><p className="font-semibold">当前 ACTIVE 伤病</p>{activeInjuries.map((injury, index) => <p className="mt-2" key={`${injury.wp_start_year}-${injury.wp_start_month}-${injury.wp_start_week}-${index}`}>{formatWpTime(injury.wp_start_year, injury.wp_start_month, injury.wp_start_week)} 至 {formatWpTime(injury.wp_end_year, injury.wp_end_month, injury.wp_end_week)}。结束周仍不可参赛，从下一 WP 周开始可报名。</p>)}</div>}</section>
                  <section className="rounded-xl border border-emerald-400/30 bg-emerald-400/5 p-5"><p className="text-xs font-semibold tracking-[0.16em] text-emerald-200">GM 最终确认 · 可编辑</p><p className="mt-2 text-sm leading-6 text-stone-400">可以改变周次或比赛；骑手与跑法可留空。数据库会重新核验 Horse 状态、Owner、伤病、时间和同周冲突。</p><div className="mt-5"><RaceScheduleForm action={confirm} catalogs={activeCatalogs} confirmation="确认以当前最终事实安排赛程吗？若与 PLAYER 请求不同，将以此最终事实公开。" defaultValues={{ wpYear: request.requested_wp_year, wpMonth: request.requested_wp_month, wpWeek: request.requested_wp_week, raceKind: request.requested_race_kind, raceCatalogId: request.requested_race_catalog_id, raceLabel: request.requested_race_label, jockey: request.requested_jockey, runningStyle: request.requested_running_style }} mode="GM_CONFIRM" pendingLabel="正在确认…" submitLabel="确认赛程" /></div></section>
                </div>
                <details className="mt-5 rounded-lg border border-red-400/25 bg-red-400/5 p-4"><summary className="cursor-pointer text-sm font-semibold text-red-100">拒绝这条报名</summary><p className="mt-2 text-sm leading-6 text-stone-300">原因可留空；如填写，会向该 PLAYER 展示。</p><ActionForm action={reject} className="mt-4 space-y-3" confirmation="确定拒绝这条 PENDING 报名吗？" pendingLabel="正在拒绝…" submitLabel="拒绝报名" variant="danger"><label className="admin-label">拒绝原因（可选）<textarea className="admin-input min-h-20" name="rejection_reason" placeholder="例如：赛程已调整" /></label></ActionForm></details>
              </article>
            );
          })}
          {!pendingRequests.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无待审核报名。</p>}
        </div>
      </section>

      <section className="mt-10 grid gap-8 xl:grid-cols-[minmax(0,0.9fr)_minmax(24rem,1.1fr)]">
        <section className="rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">GM 直接安排赛程</h2><p className="mt-2 text-sm leading-6 text-stone-400">这是独立于 PLAYER Request 的权威安排。不会创建伪造 Request，也不会让客户端传入 Owner。</p>{gameState ? <div className="mt-5"><RaceScheduleForm action={createDirectRaceEntry} catalogs={activeCatalogs} confirmation="确认直接安排这条最终赛程吗？相同最终事实的重试会返回原记录。" defaultValues={{ wpYear: gameState.current_wp_year, wpMonth: gameState.current_wp_month, wpWeek: gameState.current_wp_week, raceKind: "CATALOG" }} horses={horseOptions} mode="GM_DIRECT" pendingLabel="正在安排…" submitLabel="直接安排赛程" /></div> : <p className="mt-5 text-sm text-amber-100">请先设置 Game State。</p>}</section>
        <section className="rounded-xl border border-stone-800 bg-stone-900 p-6"><h2 className="text-xl font-semibold text-amber-200">创建比赛目录</h2><p className="mt-2 text-sm leading-6 text-stone-400">目录默认月 / 周只用于报名表单建议，不约束 GM 最终确认，也不会修改既有赛程。</p><ActionForm action={createRaceCatalog} className="mt-5 space-y-4" pendingLabel="正在创建…" submitLabel="创建固定比赛"><label className="admin-label">比赛名称<input className="admin-input" name="name" required /></label><div className="grid gap-4 sm:grid-cols-3"><label className="admin-label">Grade<select className="admin-input" defaultValue="OP" name="grade"><option value="OP">OP</option><option value="G3">G3</option><option value="G2">G2</option><option value="G1">G1</option></select></label><label className="admin-label">默认月<select className="admin-input" defaultValue="4" name="default_wp_month">{Array.from({ length: 12 }, (_, index) => index + 1).map((month) => <option key={month} value={month}>{month} 月</option>)}</select></label><label className="admin-label">默认周<select className="admin-input" defaultValue="1" name="default_wp_week">{Array.from({ length: 5 }, (_, index) => index + 1).map((week) => <option key={week} value={week}>Week {week}</option>)}</select></label></div><label className="flex items-center gap-2 text-sm text-stone-300"><input defaultChecked name="is_active" type="checkbox" />立即启用</label></ActionForm></section>
      </section>

      <details className="mt-10 rounded-xl border border-stone-800 bg-stone-900 p-6" open><summary className="cursor-pointer text-xl font-semibold text-amber-200">已确认赛程（GM 内部）</summary><p className="mt-2 text-sm text-stone-400">此区域读取 GM-only 基表，包含来源与 GM Note；PLAYER 页面不会请求这些字段。</p><div className="mt-5 grid gap-4 lg:grid-cols-2">{(entries ?? []).map((entry) => { const sourceRequest = entry.request_id ? requestsById.get(entry.request_id) : null; return <article className="rounded-lg border border-stone-800 bg-stone-950/60 p-5" key={entry.id}><div className="flex flex-col gap-3 sm:flex-row sm:justify-between"><div><p className="font-semibold text-stone-100">{horseName(horsesById.get(entry.horse_id))}</p><p className="mt-1 text-sm text-stone-400">Owner：{ownerNames.get(entry.owner_id) ?? "Owner"}</p></div><p className="font-mono text-sm text-amber-200">{formatWpTime(entry.wp_year, entry.wp_month, entry.wp_week)}</p></div><p className="mt-4 font-medium text-amber-100">{raceName(entry, catalogNames)}</p><p className="mt-2 text-sm text-stone-400">骑手：{entry.jockey || "未指定"} · 跑法：{entry.running_style || "未指定"}</p><p className="mt-3 text-xs font-semibold tracking-wide text-stone-500">来源：{entry.request_id ? "PLAYER 申请" : "GM 直接安排"}</p>{sourceRequest && <p className="mt-1 text-xs text-stone-500">原请求：{formatWpTime(sourceRequest.requested_wp_year, sourceRequest.requested_wp_month, sourceRequest.requested_wp_week)} · {requestedRaceName(sourceRequest, catalogNames)}</p>}{entry.gm_note && <p className="mt-3 rounded border border-stone-800 bg-stone-900 p-3 text-sm leading-6 text-stone-300">GM Note：{entry.gm_note}</p>}<p className="mt-3 text-xs text-stone-500">确认于 {formatDateTime(entry.confirmed_at)}</p></article>; })}{!entries?.length && <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-5 text-sm text-stone-500">暂无已确认赛程。</p>}</div></details>

      <details className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6"><summary className="cursor-pointer text-xl font-semibold text-amber-200">比赛目录管理</summary><p className="mt-2 text-sm text-stone-400">不提供物理删除。需要停止新选择时，将目录设为停用；历史 Request 与 Confirmed Entry 仍保持完整。</p><div className="mt-5 grid gap-4 lg:grid-cols-2">{(catalogs ?? []).map((catalog) => { const save = updateRaceCatalog.bind(null, catalog.id); return <article className="rounded-lg border border-stone-800 bg-stone-950/60 p-5" key={catalog.id}><ActionForm action={save} className="space-y-3" pendingLabel="正在保存…" submitLabel="保存目录"><label className="admin-label">比赛名称<input className="admin-input" defaultValue={catalog.name} name="name" required /></label><div className="grid gap-3 sm:grid-cols-3"><label className="admin-label">Grade<select className="admin-input" defaultValue={catalog.grade} name="grade"><option value="OP">OP</option><option value="G3">G3</option><option value="G2">G2</option><option value="G1">G1</option></select></label><label className="admin-label">默认月<select className="admin-input" defaultValue={catalog.default_wp_month} name="default_wp_month">{Array.from({ length: 12 }, (_, index) => index + 1).map((month) => <option key={month} value={month}>{month} 月</option>)}</select></label><label className="admin-label">默认周<select className="admin-input" defaultValue={catalog.default_wp_week} name="default_wp_week">{Array.from({ length: 5 }, (_, index) => index + 1).map((week) => <option key={week} value={week}>Week {week}</option>)}</select></label></div><label className="flex items-center gap-2 text-sm text-stone-300"><input defaultChecked={catalog.is_active} name="is_active" type="checkbox" />允许新报名与新确认选择</label></ActionForm></article>; })}{!catalogs?.length && <p className="rounded-lg border border-stone-800 bg-stone-950/60 p-5 text-sm text-stone-500">尚无比赛目录。</p>}</div></details>
    </main>
  );
}
