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
      ? "inline-flex min-h-11 items-center justify-center rounded-xl border border-[#c97a74] px-4 py-2.5 text-sm font-semibold text-[#8f322e] hover:bg-[#f8e4e2] disabled:cursor-not-allowed disabled:opacity-60"
      : variant === "secondary"
        ? "inline-flex min-h-11 items-center justify-center rounded-xl border border-[#c9c0b2] px-4 py-2.5 text-sm font-semibold text-[#4e5952] hover:border-[#b58a3c] hover:bg-[#f4ead0] hover:text-[#173f35] disabled:cursor-not-allowed disabled:opacity-60"
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
          className="mt-3 rounded-xl border border-[#d7c393] bg-[#f4ead0] p-4 text-sm text-[#735421]"
          role="alert"
        >
          <p>{confirmation}</p>
          <div className="mt-3 flex flex-wrap gap-2">
            <button
              className="inline-flex min-h-11 items-center justify-center rounded-xl border border-[#c9c0b2] bg-white px-4 py-2.5 text-sm font-semibold text-[#4e5952] hover:border-[#b58a3c] hover:text-[#173f35]"
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
              ? "inline-flex min-h-11 items-center justify-center rounded-xl border border-[#c97a74] px-4 py-2.5 text-sm font-semibold text-[#8f322e] hover:bg-[#f8e4e2]"
              : variant === "secondary"
                ? "inline-flex min-h-11 items-center justify-center rounded-xl border border-[#c9c0b2] px-4 py-2.5 text-sm font-semibold text-[#4e5952] hover:border-[#b58a3c] hover:bg-[#f4ead0] hover:text-[#173f35]"
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
