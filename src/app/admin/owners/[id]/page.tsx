import { randomUUID } from "node:crypto";

import Link from "next/link";
import { notFound } from "next/navigation";

import { adjustOwnerFunds, updateOwner } from "@/app/admin/actions";
import { ActionForm } from "@/components/action-form";
import { Notice } from "@/components/notice";
import { requireGM } from "@/lib/auth/session";
import { formatDateTime, formatGameMoney } from "@/lib/format";

type PageProps = {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ notice?: string }>;
};

type FinancialSummary = {
  account_funds: string | number;
  foal_trade_frozen_funds: string | number;
  public_auction_frozen_funds: string | number;
  total_frozen_funds: string | number;
  available_funds: string | number;
};

type FinancialTransaction = {
  id: string;
  amount: string | number;
  transaction_kind: string;
  source_entity_type: string | null;
  effective_at: string;
  reason: string | null;
};

function transactionKindLabel(kind: string) {
  const labels: Record<string, string> = {
    GM_MANUAL_ADJUSTMENT: "GM 手工调整",
    FOAL_TRADE_PURCHASE: "庭先成交扣款",
    PUBLIC_AUCTION_PURCHASE: "公开拍卖成交扣款",
    PUBLIC_AUCTION_ROLLBACK: "公开拍卖回滚补偿",
    PRIZE_RELEASE: "奖金释放",
    PRIZE_CORRECTION: "奖金更正",
    PRIZE_VOID_REVERSAL: "奖金作废冲回",
  };

  return labels[kind] ?? kind;
}

export default async function AdminOwnerDetailPage({ params, searchParams }: PageProps) {
  const [{ id }, { notice }, { supabase }] = await Promise.all([params, searchParams, requireGM()]);
  const [ownerResult, summaryResult, transactionsResult] = await Promise.all([
    supabase
      .from("owners")
      .select("id, display_name, initial_funds, created_at, updated_at")
      .eq("id", id)
      .maybeSingle(),
    supabase.rpc("get_gm_owner_financial_summary", { p_owner_id: id }),
    supabase
      .from("financial_transactions")
      .select("id, amount, transaction_kind, source_entity_type, effective_at, reason")
      .eq("owner_id", id)
      .order("effective_at", { ascending: false })
      .order("id", { ascending: false })
      .limit(30),
  ]);

  const owner = ownerResult.data;
  if (!owner) {
    notFound();
  }

  const summary = (summaryResult.data?.[0] ?? null) as FinancialSummary | null;
  const transactions = (transactionsResult.data ?? []) as FinancialTransaction[];
  const adjustmentRequestId = randomUUID();

  return (
    <main className="mx-auto w-full max-w-5xl px-6 py-10">
      <Link className="text-sm text-amber-200 hover:text-amber-100" href="/admin/owners">
        ← 马主管理
      </Link>
      <h1 className="mt-5 text-3xl font-semibold tracking-tight">{owner.display_name}</h1>
      <Notice message={notice} />

      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <dl className="grid gap-4 text-sm sm:grid-cols-2">
          <div>
            <dt className="text-stone-500">初始资金</dt>
            <dd className="mt-1 font-mono text-stone-100">{formatGameMoney(owner.initial_funds)}</dd>
          </div>
          <div>
            <dt className="text-stone-500">创建时间</dt>
            <dd className="mt-1 text-stone-100">{formatDateTime(owner.created_at)}</dd>
          </div>
        </dl>
        <form action={updateOwner.bind(null, owner.id)} className="mt-8 max-w-md space-y-4 border-t border-stone-800 pt-6">
          <label className="block text-sm text-stone-300" htmlFor="display_name">
            公开名称
            <input className="admin-input" defaultValue={owner.display_name} id="display_name" name="display_name" required />
          </label>
          <p className="text-xs leading-5 text-stone-500">初始资金不会出现在编辑表单中，数据库也会拒绝直接修改。</p>
          <button className="admin-button">保存公开资料</button>
        </form>
      </section>

      <section className="mt-6 rounded-xl border border-amber-300/25 bg-stone-900 p-6">
        <p className="text-xs font-semibold tracking-[0.16em] text-amber-300">GM ONLY · FUNDS</p>
        <h2 className="mt-2 text-2xl font-semibold text-stone-100">资金汇总与受控调整</h2>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-stone-400">资金不会直接改写。每次调整都会追加一笔 `GM_MANUAL_ADJUSTMENT` 正式流水和一条审计记录；扣减后账户资金与可用资金都不得为负。</p>

        {summary ? (
          <>
            <dl className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
              {[
                ["账户资金", summary.account_funds, "text-emerald-100"],
                ["庭先冻结", summary.foal_trade_frozen_funds, "text-amber-100"],
                ["公开拍卖冻结", summary.public_auction_frozen_funds, "text-amber-100"],
                ["冻结合计", summary.total_frozen_funds, "text-amber-100"],
                ["当前可用资金", summary.available_funds, "text-sky-100"],
              ].map(([label, value, className]) => (
                <div className="rounded-lg border border-stone-800 bg-stone-950/55 p-4" key={String(label)}>
                  <dt className="text-xs text-stone-500">{label}</dt>
                  <dd className={`mt-2 break-all font-mono text-lg font-semibold ${className}`}>{formatGameMoney(value as string | number)}</dd>
                </div>
              ))}
            </dl>

            <ActionForm
              action={adjustOwnerFunds.bind(null, owner.id)}
              className="mt-6 grid gap-4 rounded-lg border border-red-400/30 bg-red-400/5 p-5 lg:grid-cols-2"
              confirmation="请再次确认：这会立即追加一笔不可编辑、不可删除的正式资金流水，并写入 GM 审计记录。"
              pendingLabel="正在写入资金流水…"
              submitLabel="提交资金调整"
              variant="danger"
            >
              <input name="request_id" type="hidden" value={adjustmentRequestId} />
              <label className="admin-label">
                调整方向
                <select className="admin-input" defaultValue="CREDIT" name="direction" required>
                  <option value="CREDIT">增加资金</option>
                  <option value="DEBIT">扣减资金</option>
                </select>
              </label>
              <label className="admin-label">
                金额（正整数游戏资金单位）
                <input className="admin-input" inputMode="numeric" min="1" name="amount" required step="1" type="number" />
              </label>
              <label className="admin-label lg:col-span-2">
                调整原因（必填，会进入审计）
                <textarea className="admin-input min-h-24" name="reason" placeholder="例如：修正首次配发遗漏；说明事实、金额来源与裁定理由" required />
              </label>
              <p className="text-xs leading-5 text-red-100 lg:col-span-2">调整不改变任何冻结报价或历史流水；若扣减会导致账户资金或可用资金为负，数据库会拒绝。本页显示的数据仅供复核，提交时数据库会重新计算。</p>
            </ActionForm>
          </>
        ) : (
          <div className="mt-6 rounded-lg border border-red-400/35 bg-red-400/5 p-4 text-sm leading-6 text-red-100">资金汇总当前无法读取，因此已隐藏手工调整入口。请刷新页面；如问题持续，请检查 GM 权限与数据库 migration 状态。</div>
        )}
      </section>

      <section className="mt-6 rounded-xl border border-stone-800 bg-stone-900 p-6">
        <p className="text-xs font-semibold tracking-[0.16em] text-stone-500">GM ONLY · LEDGER</p>
        <h2 className="mt-2 text-2xl font-semibold text-stone-100">正式资金流水</h2>
        <p className="mt-2 text-sm leading-6 text-stone-400">最近 30 笔。这里只读；任何更正都必须通过新增对应流水完成。</p>
        <div className="mt-5 overflow-x-auto rounded-lg border border-stone-800">
          <table className="min-w-[44rem] w-full text-left text-sm">
            <thead className="bg-stone-950 text-stone-500">
              <tr>
                <th className="px-4 py-3 font-medium">时间</th>
                <th className="px-4 py-3 font-medium">类别</th>
                <th className="px-4 py-3 text-right font-medium">金额</th>
                <th className="px-4 py-3 font-medium">原因 / 来源</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-800">
              {transactions.map((transaction) => {
                const isCredit = BigInt(transaction.amount) > 0;
                return (
                  <tr key={transaction.id}>
                    <td className="whitespace-nowrap px-4 py-3 text-stone-400">{formatDateTime(transaction.effective_at)}</td>
                    <td className="px-4 py-3 text-stone-200">{transactionKindLabel(transaction.transaction_kind)}</td>
                    <td className={`px-4 py-3 text-right font-mono font-semibold ${isCredit ? "text-emerald-100" : "text-red-200"}`}>{formatGameMoney(transaction.amount)}</td>
                    <td className="px-4 py-3 text-stone-400">{transaction.reason || transaction.source_entity_type || "—"}</td>
                  </tr>
                );
              })}
              {!transactions.length && <tr><td className="px-4 py-6 text-stone-500" colSpan={4}>尚无正式资金流水。</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
    </main>
  );
}
