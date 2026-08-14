import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

const CONNECTION_PROBE_TABLE = "__horserpg_connection_check";

export default async function SupabaseTestPage() {
  const supabase = await createClient();
  const { error } = await supabase
    .from(CONNECTION_PROBE_TABLE)
    .select("*")
    .limit(1);

  const isExpectedMissingTable =
    error?.code === "PGRST205" && error.message.includes(CONNECTION_PROBE_TABLE);
  const isConnected = !error || isExpectedMissingTable;

  return (
    <main className="flex min-h-screen items-center justify-center bg-stone-950 px-6 text-stone-100">
      <section className="w-full max-w-xl rounded-2xl border border-amber-200/20 bg-stone-900 p-8 shadow-2xl shadow-black/20 sm:p-12">
        <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">SUPABASE</p>
        <h1 className="mt-4 text-3xl font-semibold tracking-tight">数据库连接测试</h1>
        <p className="mt-5 leading-7 text-stone-300">
          {isConnected
            ? "连接成功：Supabase 已响应数据库 API。"
            : "连接未通过：请检查本地环境变量和 Supabase 项目状态。"}
        </p>
        <p className="mt-4 text-sm leading-6 text-stone-400">
          本页只读取一个特意不存在的占位表，不会创建表、写入数据或访问业务数据。
        </p>
        {!isConnected && (
          <p className="mt-4 rounded-lg bg-red-950/50 px-4 py-3 text-sm text-red-200">
            错误代码：{error?.code ?? "网络或配置错误"}
          </p>
        )}
      </section>
    </main>
  );
}
