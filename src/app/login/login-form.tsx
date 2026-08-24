"use client";

import { useActionState } from "react";

import { signIn, type LoginState } from "@/app/actions/auth";

const initialState: LoginState = {};

export function LoginForm() {
  const [state, formAction, pending] = useActionState(signIn, initialState);

  return (
    <form action={formAction} className="mt-8 space-y-5">
      <label className="block text-sm font-semibold text-[#3f4943]" htmlFor="email">
        邮箱
        <input
          autoComplete="email"
          className="mt-2 min-h-12 w-full rounded-xl border border-[#cfc6b8] bg-[#fffdf8] px-4 py-3 text-[#202521] outline-none placeholder:text-[#9da39f] hover:border-[#aca292] focus:border-[#b58a3c] focus:ring-4 focus:ring-[#b58a3c]/10"
          id="email"
          name="email"
          placeholder="name@example.com"
          required
          type="email"
        />
      </label>
      <label className="block text-sm font-semibold text-[#3f4943]" htmlFor="password">
        密码
        <input
          autoComplete="current-password"
          className="mt-2 min-h-12 w-full rounded-xl border border-[#cfc6b8] bg-[#fffdf8] px-4 py-3 text-[#202521] outline-none placeholder:text-[#9da39f] hover:border-[#aca292] focus:border-[#b58a3c] focus:ring-4 focus:ring-[#b58a3c]/10"
          id="password"
          name="password"
          placeholder="输入登录密码"
          required
          type="password"
        />
      </label>
      {state.error && (
        <p aria-live="polite" className="rounded-xl border border-[#dca9a5] bg-[#f8e4e2] px-4 py-3 text-sm text-[#8f322e]">
          {state.error}
        </p>
      )}
      <button
        className="min-h-12 w-full rounded-xl bg-[#173f35] px-4 py-3 font-semibold text-white shadow-[0_10px_24px_rgb(23_63_53/18%)] hover:-translate-y-0.5 hover:bg-[#245649] disabled:cursor-not-allowed disabled:opacity-70"
        disabled={pending}
        type="submit"
      >
        {pending ? "登录中…" : "登录"}
      </button>
    </form>
  );
}
