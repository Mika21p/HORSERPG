import { AppShell } from "@/components/app-shell";
import { ActionForm } from "@/components/action-form";
import { Notice } from "@/components/notice";
import { RaceScheduleForm, type RaceHorseOption } from "@/components/race-schedule-form";
import { PageHeader } from "@/components/ui/primitives";
import { submitRaceEntryRequest, withdrawRaceEntryRequest } from "@/app/races/actions";
import { requirePlayer } from "@/lib/auth/session";
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

type RaceResolution = {
  request_id: string;
  confirmed_entry_id: string;
  wp_year: number;
  wp_month: number;
  wp_week: number;
  race_kind: string;
  race_catalog_id: string | null;
  race_label: string | null;
  jockey: string | null;
  running_style: string | null;
  confirmed_at: string;
};

function horseName(horse: { translated_name: string | null; foal_name: string } | undefined) {
  return horse?.translated_name || horse?.foal_name || "Horse";
}

function raceName(entry: RaceIdentity, catalogNames: Map<string, string>) {
  if (entry.race_kind === "CATALOG") {
    return entry.race_catalog_id ? catalogNames.get(entry.race_catalog_id) ?? "固定比赛" : "固定比赛";
  }

  return entry.race_label || formatRaceKind(entry.race_kind);
}

function requestedRaceName(entry: { requested_race_kind: string; requested_race_catalog_id: string | null; requested_race_label: string | null }, catalogNames: Map<string, string>) {
  return raceName({
    race_kind: entry.requested_race_kind,
    race_catalog_id: entry.requested_race_catalog_id,
    race_label: entry.requested_race_label,
  }, catalogNames);
}

function statusClass(status: string) {
  if (status === "CONFIRMED") return "border-emerald-400/40 bg-emerald-400/10 text-emerald-100";
  if (status === "PENDING") return "border-amber-300/40 bg-amber-300/10 text-amber-100";
  if (status === "REJECTED") return "border-red-400/40 bg-red-400/10 text-red-100";
  return "border-stone-700 bg-stone-800 text-stone-300";
}

export const dynamic = "force-dynamic";

export default async function RacesPage({ searchParams }: PageProps) {
  const [{ supabase, user, profile }, { notice }] = await Promise.all([requirePlayer(), searchParams]);
  const [{ data: gameState, error: gameStateError }, { data: catalogs, error: catalogError }, { data: horses, error: horseError }, { data: requests, error: requestError }, { data: resolutions, error: resolutionError }, { data: publicEntries, error: publicScheduleError }, { data: allHorses, error: allHorseError }, { data: owners, error: ownerError }] = await Promise.all([
    supabase.from("game_state").select("current_wp_year, current_wp_month, current_wp_week").maybeSingle(),
    supabase.from("race_catalog").select("id, name, grade, default_wp_month, default_wp_week, is_active").order("name"),
    supabase.from("horses").select("id, horse_number, foal_name, translated_name, owner_id, life_stage, current_jockey_name").eq("owner_id", profile.owner_id).order("horse_number"),
    supabase.from("race_entry_requests").select("id, horse_id, requested_wp_year, requested_wp_month, requested_wp_week, requested_race_kind, requested_race_catalog_id, requested_race_label, requested_jockey, requested_running_style, player_note, status, rejection_reason, created_at, reviewed_at, withdrawn_at").order("created_at", { ascending: false }),
    supabase.rpc("get_current_player_race_entry_resolutions"),
    supabase.from("confirmed_race_entries_public").select("id, horse_id, owner_id, wp_year, wp_month, wp_week, race_kind, race_catalog_id, race_label, jockey, running_style, confirmed_at").order("wp_year").order("wp_month").order("wp_week").order("confirmed_at"),
    supabase.from("horses").select("id, foal_name, translated_name").order("horse_number"),
    supabase.from("owners").select("id, display_name").order("display_name"),
  ]);

  const horseIds = (horses ?? []).map((horse) => horse.id);
  const { data: injuries, error: injuryError } = horseIds.length
    ? await supabase
      .from("injuries_public")
      .select("horse_id, wp_start_year, wp_start_month, wp_start_week, wp_end_year, wp_end_month, wp_end_week")
      .eq("status", "ACTIVE")
      .in("horse_id", horseIds)
    : { data: [], error: null };

  const dataError = gameStateError || catalogError || horseError || requestError || resolutionError || publicScheduleError || allHorseError || ownerError || injuryError;
  const catalogNames = new Map((catalogs ?? []).map((catalog) => [catalog.id, catalog.name]));
  const ownHorsesById = new Map((horses ?? []).map((horse) => [horse.id, horse]));
  const allHorsesById = new Map((allHorses ?? []).map((horse) => [horse.id, horse]));
  const ownerNames = new Map((owners ?? []).map((owner) => [owner.id, owner.display_name]));
  const resolutionRows = (resolutions ?? []) as RaceResolution[];
  const resolutionsByRequestId = new Map(resolutionRows.map((resolution) => [resolution.request_id, resolution]));
  const injuriesByHorseId = new Map<string, NonNullable<typeof injuries>>();
  for (const injury of injuries ?? []) {
    injuriesByHorseId.set(injury.horse_id, [...(injuriesByHorseId.get(injury.horse_id) ?? []), injury]);
  }

  const horseOptions: RaceHorseOption[] = (horses ?? []).map((horse) => ({
    ...horse,
    injuries: injuriesByHorseId.get(horse.id) ?? [],
  }));
  const activeCatalogs = (catalogs ?? []).filter((catalog) => catalog.is_active);
  const ownSchedule = (publicEntries ?? []).filter((entry) => entry.owner_id === profile.owner_id);

  return (
    <AppShell email={user.email} isGM={false}>
      <main className="page-wrap">
        <PageHeader
          action={<div className="rounded-xl border border-[#d7c393] bg-[#f4ead0] px-5 py-4 text-sm">
            <p className="text-stone-500">当前 Winning Post 时间</p>
            <p className="mt-1 font-semibold text-[#173f35]">{gameState ? formatWpTime(gameState.current_wp_year, gameState.current_wp_month, gameState.current_wp_week) : "尚未由 GM 初始化"}</p>
          </div>}
          description="提交的是报名意向，只有 GM 确认后才会成为公开赛程。你的原始请求会与最终确认事实并列保存。"
          eyebrow="RACE MANAGEMENT"
          title="比赛报名与赛程"
        />

        <Notice message={notice} />
        {dataError && <p className="mt-5 rounded-xl border border-red-400/40 bg-red-400/5 p-4 text-sm leading-6 text-red-100">部分比赛数据暂时无法读取。请刷新页面；不会显示任何数据库内部错误。</p>}

        <div className="mt-8 grid gap-8 xl:grid-cols-[minmax(0,0.92fr)_minmax(22rem,1.08fr)]">
          <section className="h-fit rounded-xl border border-stone-800 bg-stone-900 p-6">
            <h2 className="text-xl font-semibold text-amber-200">提交报名意向</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">仅 ACTIVE Horse 可选。固定比赛会建议默认月 / 周，但你始终可以自行调整申请时间。</p>
            {gameState ? (
              <div className="mt-5">
                <RaceScheduleForm
                  action={submitRaceEntryRequest}
                  catalogs={activeCatalogs}
                  defaultValues={{
                    wpYear: gameState.current_wp_year,
                    wpMonth: gameState.current_wp_month,
                    wpWeek: gameState.current_wp_week,
                    raceKind: "CATALOG",
                  }}
                  horses={horseOptions}
                  mode="PLAYER_REQUEST"
                  pendingLabel="正在提交…"
                  submitLabel="提交报名意向"
                />
              </div>
            ) : <p className="mt-5 rounded-lg border border-amber-300/30 bg-amber-300/5 p-4 text-sm text-amber-100">GM 尚未设置 Game State，当前不能提交报名。</p>}
          </section>

          <section>
            <div className="flex items-end justify-between gap-4">
              <div><h2 className="text-xl font-semibold text-amber-200">我的报名历史</h2><p className="mt-2 text-sm text-stone-400">PENDING 可撤回；已确认记录会精准显示 GM 最终赛程。</p></div>
              <span className="font-mono text-sm text-stone-500">{requests?.length ?? 0} 条</span>
            </div>
            <div className="mt-5 space-y-4">
              {(requests ?? []).map((request) => {
                const resolution = resolutionsByRequestId.get(request.id);
                const withdraw = withdrawRaceEntryRequest.bind(null, request.id);
                return (
                  <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={request.id}>
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div><p className="font-semibold text-stone-100">{horseName(ownHorsesById.get(request.horse_id))}</p><p className="mt-1 text-xs text-stone-500">提交于 {formatDateTime(request.created_at)}</p></div>
                      <span className={`w-fit rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(request.status)}`}>{formatRaceEntryRequestStatus(request.status)}</span>
                    </div>
                    <div className={`mt-5 grid gap-4 ${request.status === "CONFIRMED" ? "lg:grid-cols-2" : ""}`}>
                      <section className="rounded-lg border border-stone-800 bg-stone-950/60 p-4"><p className="text-xs font-semibold tracking-[0.14em] text-stone-500">PLAYER 原始请求</p><p className="mt-2 font-medium text-stone-100">{formatWpTime(request.requested_wp_year, request.requested_wp_month, request.requested_wp_week)}</p><p className="mt-1 text-sm text-amber-100">{requestedRaceName(request, catalogNames)}</p><p className="mt-2 text-sm text-stone-400">希望骑手：{request.requested_jockey || "未指定"} · 跑法：{request.requested_running_style || "未指定"}</p>{request.player_note && <p className="mt-2 text-sm leading-6 text-stone-400">备注：{request.player_note}</p>}</section>
                      {request.status === "CONFIRMED" && (
                        <section className="rounded-lg border border-emerald-400/35 bg-emerald-400/5 p-4"><p className="text-xs font-semibold tracking-[0.14em] text-emerald-200">GM 最终确认</p>{resolution ? <><p className="mt-2 font-medium text-stone-100">{formatWpTime(resolution.wp_year, resolution.wp_month, resolution.wp_week)}</p><p className="mt-1 text-sm text-emerald-100">{raceName(resolution, catalogNames)}</p><p className="mt-2 text-sm text-stone-400">骑手：{resolution.jockey || "未指定"} · 跑法：{resolution.running_style || "未指定"}</p><p className="mt-2 text-xs text-stone-500">确认于 {formatDateTime(resolution.confirmed_at)}</p></> : <p className="mt-2 text-sm leading-6 text-amber-100">最终确认映射暂时未读取到。请刷新；不会以 Horse、时间或比赛名称猜测关联。</p>}</section>
                      )}
                    </div>
                    {request.status === "REJECTED" && <p className="mt-4 rounded-lg border border-red-400/30 bg-red-400/5 p-3 text-sm text-red-100">已拒绝{request.rejection_reason ? `：${request.rejection_reason}` : "。"}</p>}
                    {request.status === "WITHDRAWN" && <p className="mt-4 text-sm text-stone-400">已于 {formatDateTime(request.withdrawn_at)} 撤回。</p>}
                    {request.status === "PENDING" && <ActionForm action={withdraw} className="mt-4" confirmation="确定撤回这条报名意向吗？撤回后不能通过普通页面恢复。" pendingLabel="正在撤回…" submitLabel="撤回报名" variant="secondary" />}
                  </article>
                );
              })}
              {!requests?.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">尚未提交比赛报名意向。</p>}
            </div>
          </section>
        </div>

        <section className="mt-10">
          <h2 className="text-xl font-semibold text-amber-200">我的已确认赛程</h2>
          <p className="mt-2 text-sm text-stone-400">以下为公开确认事实，历史确认不会因 Game State 推进而消失。</p>
          <ScheduleList catalogNames={catalogNames} entries={ownSchedule} horses={allHorsesById} owners={ownerNames} />
        </section>

        <section className="mt-10 border-t border-stone-800 pt-10">
          <h2 className="text-xl font-semibold text-amber-200">公开已确认赛程</h2>
          <p className="mt-2 text-sm text-stone-400">只读取公开赛程投影；不显示报名来源、GM Note 或确认 GM。</p>
          <ScheduleList catalogNames={catalogNames} entries={publicEntries ?? []} horses={allHorsesById} owners={ownerNames} />
        </section>
      </main>
    </AppShell>
  );
}

function ScheduleList({
  catalogNames,
  entries,
  horses,
  owners,
}: {
  catalogNames: Map<string, string>;
  entries: Array<{ id: string; horse_id: string; owner_id: string; wp_year: number; wp_month: number; wp_week: number; race_kind: string; race_catalog_id: string | null; race_label: string | null; jockey: string | null; running_style: string | null; confirmed_at: string }>;
  horses: Map<string, { foal_name: string; translated_name: string | null }>;
  owners: Map<string, string>;
}) {
  return (
    <div className="mt-5 grid gap-4 lg:grid-cols-2">
      {entries.map((entry) => <article className="rounded-xl border border-stone-800 bg-stone-900 p-5" key={entry.id}><div className="flex flex-col gap-3 sm:flex-row sm:justify-between"><div><p className="font-semibold text-stone-100">{horseName(horses.get(entry.horse_id))}</p><p className="mt-1 text-sm text-stone-400">Owner：{owners.get(entry.owner_id) ?? "Owner"}</p></div><p className="font-mono text-sm text-amber-200">{formatWpTime(entry.wp_year, entry.wp_month, entry.wp_week)}</p></div><p className="mt-4 font-medium text-amber-100">{raceName(entry, catalogNames)}</p><p className="mt-2 text-sm text-stone-400">骑手：{entry.jockey || "未指定"} · 跑法：{entry.running_style || "未指定"}</p><p className="mt-2 text-xs text-stone-500">确认于 {formatDateTime(entry.confirmed_at)}</p></article>)}
      {!entries.length && <p className="rounded-xl border border-stone-800 bg-stone-900 p-6 text-sm text-stone-500">暂无已确认赛程。</p>}
    </div>
  );
}
