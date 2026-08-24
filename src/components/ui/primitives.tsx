type CommonProps = { children: React.ReactNode; className?: string };

function classes(base: string, className?: string) {
  return className ? `${base} ${className}` : base;
}

export function PageHeader({ action, description, eyebrow, title }: {
  action?: React.ReactNode;
  description?: React.ReactNode;
  eyebrow?: string;
  title: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-5 border-b border-[#d8d0c2] pb-7 md:flex-row md:items-end md:justify-between">
      <div className="min-w-0">
        {eyebrow && <p className="page-eyebrow">{eyebrow}</p>}
        <h1 className="page-title">{title}</h1>
        {description && <div className="page-description">{description}</div>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </section>
  );
}

export function Surface({ children, className }: CommonProps) {
  return <section className={classes("club-card", className)}>{children}</section>;
}

export function SectionHeader({ action, description, title }: {
  action?: React.ReactNode;
  description?: React.ReactNode;
  title: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
      <div>
        <h2 className="display-title text-xl font-semibold text-[#173f35]">{title}</h2>
        {description && <div className="mt-1 text-sm leading-6 text-[#68736c]">{description}</div>}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  );
}

export function EmptyState({ children, className }: CommonProps) {
  return <div className={classes("rounded-xl border border-dashed border-[#cfc6b8] bg-[#f8f4ed] p-6 text-center text-sm text-[#737c76]", className)}>{children}</div>;
}

export function StatusBadge({ children, tone = "neutral" }: CommonProps & { tone?: "danger" | "info" | "neutral" | "success" | "warning" }) {
  const tones = {
    danger: "border-[#dca9a5] bg-[#f8e4e2] text-[#8f322e]",
    info: "border-[#abc6d5] bg-[#e5f0f5] text-[#315f7a]",
    neutral: "border-[#d8d0c2] bg-[#eee9df] text-[#59635c]",
    success: "border-[#a8cbb8] bg-[#e2f0e8] text-[#246647]",
    warning: "border-[#d7c393] bg-[#f4ead0] text-[#735421]",
  };
  return <span className={`inline-flex w-fit rounded-full border px-3 py-1 text-xs font-bold ${tones[tone]}`}>{children}</span>;
}
