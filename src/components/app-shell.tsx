import { signOut } from "@/app/actions/auth";
import { AppNavigation } from "@/components/app-navigation";
import { createClient } from "@/lib/supabase/server";

type AppShellProps = {
  children: React.ReactNode;
  email: string | undefined;
  isGM: boolean;
};

export async function AppShell({ children, email, isGM }: AppShellProps) {
  const supabase = await createClient();
  const { data: gameState } = await supabase
    .from("game_state")
    .select("current_wp_year, current_wp_month, current_wp_week")
    .maybeSingle();
  const gameTime = gameState
    ? `${gameState.current_wp_year}年 ${String(gameState.current_wp_month).padStart(2, "0")}月 第${gameState.current_wp_week}周`
    : "尚未由 GM 设置";
  const accountActions = (
    <form action={signOut}>
      <button className="min-h-11 rounded-xl border border-[#cfc6b8] px-3 py-2 text-xs font-semibold text-[#4e5952] hover:border-[#b58a3c] hover:bg-[#f4ead0] hover:text-[#173f35]">
        退出登录
      </button>
    </form>
  );

  return (
    <div className="app-theme-light min-h-screen bg-[#f4f0e7] text-[#202521]">
      <AppNavigation accountActions={accountActions} email={email} gameTime={gameTime} isGM={isGM} />
      <div className="min-w-0 lg:ml-[248px]">{children}</div>
    </div>
  );
}
