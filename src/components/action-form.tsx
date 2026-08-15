"use client";

import { useState } from "react";
import { useFormStatus } from "react-dom";

type ServerAction = (formData: FormData) => void | Promise<void>;

type ActionFormProps = {
  action: ServerAction;
  children?: React.ReactNode;
  className?: string;
  confirmation?: string;
  pendingLabel: string;
  submitLabel: string;
  variant?: "primary" | "danger" | "secondary";
};

function SubmitButton({
  pendingLabel,
  submitLabel,
  variant = "primary",
}: Pick<ActionFormProps, "pendingLabel" | "submitLabel" | "variant">) {
  const { pending } = useFormStatus();
  const className =
    variant === "danger"
      ? "inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10 disabled:cursor-not-allowed disabled:opacity-60"
      : variant === "secondary"
        ? "inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300 hover:text-amber-200 disabled:cursor-not-allowed disabled:opacity-60"
        : "admin-button";

  return (
    <button
      className={className}
      disabled={pending}
      type="submit"
    >
      {pending ? pendingLabel : submitLabel}
    </button>
  );
}

export function ActionForm({
  action,
  children,
  className,
  confirmation,
  pendingLabel,
  submitLabel,
  variant,
}: ActionFormProps) {
  const [awaitingConfirmation, setAwaitingConfirmation] = useState(false);

  return (
    <form action={action} className={className}>
      {children}
      {confirmation && awaitingConfirmation ? (
        <div
          aria-live="polite"
          className="mt-3 rounded-lg border border-amber-300/50 bg-amber-100/10 p-3 text-sm text-amber-100"
          role="alert"
        >
          <p>{confirmation}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              className="inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300 hover:text-amber-200"
              onClick={() => setAwaitingConfirmation(false)}
              type="button"
            >
              取消
            </button>
            <SubmitButton
              pendingLabel={pendingLabel}
              submitLabel="确认执行"
              variant={variant}
            />
          </div>
        </div>
      ) : confirmation ? (
        <button
          className={
            variant === "danger"
              ? "inline-flex items-center justify-center rounded-lg border border-red-400/60 px-4 py-2.5 text-sm font-semibold text-red-200 hover:bg-red-400/10"
              : variant === "secondary"
                ? "inline-flex items-center justify-center rounded-lg border border-stone-600 px-4 py-2.5 text-sm font-semibold text-stone-200 hover:border-amber-300 hover:text-amber-200"
                : "admin-button"
          }
          onClick={() => setAwaitingConfirmation(true)}
          type="button"
        >
          {submitLabel}
        </button>
      ) : (
        <SubmitButton
          pendingLabel={pendingLabel}
          submitLabel={submitLabel}
          variant={variant}
        />
      )}
    </form>
  );
}
