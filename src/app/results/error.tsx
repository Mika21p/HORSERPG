"use client";

export default function ResultsError({ reset }: { error: Error; reset: () => void }) {
  return <main className="mx-auto w-full max-w-6xl px-6 py-10"><section className="rounded-xl border border-red-400/40 bg-red-400/5 p-6"><h1 className="text-xl font-semibold text-red-100">公开比赛结果暂时无法加载</h1><p className="mt-2 text-sm leading-6 text-stone-300">请稍后重试；页面不会显示内部错误或数据库信息。</p><button className="mt-5 rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-100 hover:bg-red-400/10" onClick={reset} type="button">重新尝试</button></section></main>;
}
