export default function Home() {
  return (
    <main className="flex min-h-screen items-center justify-center bg-stone-950 px-6 text-stone-100">
      <section className="w-full max-w-xl rounded-2xl border border-amber-200/20 bg-stone-900 p-8 shadow-2xl shadow-black/20 sm:p-12">
        <p className="text-sm font-semibold tracking-[0.24em] text-amber-300">HORSE RPG</p>
        <h1 className="mt-4 text-4xl font-semibold tracking-tight sm:text-5xl">基础工程已就绪</h1>
        <p className="mt-5 leading-7 text-stone-300">
          这里将成为在线赛马跑团管理平台。认证、比赛、拍卖与数据模型将在后续阶段按需求逐步构建。
        </p>
      </section>
    </main>
  );
}
