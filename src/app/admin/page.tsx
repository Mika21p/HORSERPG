import Link from "next/link";

const links = [
  ["Owners", "/admin/owners", "创建与维护 Owner 公开基础资料"],
  ["Horses", "/admin/horses", "创建与维护 Horse 及 Horse Factors"],
  ["Users", "/admin/users", "创建 PLAYER 并绑定空闲 Owner"],
  ["Game State", "/admin/game-state", "设置当前 Winning Post 时间"],
] as const;

export default function AdminHomePage() {
  return (
    <main className="mx-auto w-full max-w-6xl px-6 py-10">
      <h1 className="text-3xl font-semibold tracking-tight">GM 后台</h1>
      <p className="mt-3 text-stone-400">第一阶段只维护已发布的 Core Schema 数据。</p>
      <div className="mt-8 grid gap-4 sm:grid-cols-2">
        {links.map(([title, href, description]) => (
          <Link
            className="rounded-xl border border-stone-800 bg-stone-900 p-5 transition hover:border-amber-300/60 hover:bg-stone-800"
            href={href}
            key={href}
          >
            <h2 className="font-semibold text-amber-200">{title}</h2>
            <p className="mt-2 text-sm leading-6 text-stone-400">{description}</p>
          </Link>
        ))}
      </div>
    </main>
  );
}
