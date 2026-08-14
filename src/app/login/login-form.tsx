"use client";

import { useActionState } from "react";

import { signIn, type LoginState } from "@/app/actions/auth";

const initialState: LoginState = {};

export function LoginForm() {
  const [state, formAction, pending] = useActionState(signIn, initialState);

  return (
    <form action={formAction} className="mt-8 space-y-5">
      <label className="block text-sm font-medium text-stone-200" htmlFor="email">
        Email
        <input
          autoComplete="email"
          className="mt-2 w-full rounded-lg border border-stone-700 bg-stone-950 px-3 py-2.5 text-stone-100 outline-none placeholder:text-stone-600 focus:border-amber-300"
          id="email"
          name="email"
          required
          type="email"
        />
      </label>
      <label className="block text-sm font-medium text-stone-200" htmlFor="password">
        Password
        <input
          autoComplete="current-password"
          className="mt-2 w-full rounded-lg border border-stone-700 bg-stone-950 px-3 py-2.5 text-stone-100 outline-none placeholder:text-stone-600 focus:border-amber-300"
          id="password"
          name="password"
          required
          type="password"
        />
      </label>
      {state.error && (
        <p aria-live="polite" className="rounded-lg bg-red-950/60 px-3 py-2 text-sm text-red-200">
          {state.error}
        </p>
      )}
      <button
        className="w-full rounded-lg bg-amber-300 px-4 py-2.5 font-semibold text-stone-950 hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-70"
        disabled={pending}
        type="submit"
      >
        {pending ? "登录中…" : "登录"}
      </button>
    </form>
  );
}
