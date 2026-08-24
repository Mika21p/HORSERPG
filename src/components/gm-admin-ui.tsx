import Link from "next/link";

type SectionLink = {
  count?: number;
  href: string;
  label: string;
};

export function GMPageHeader({
  action,
  description,
  eyebrow,
  status,
  title,
}: {
  action?: React.ReactNode;
  description: React.ReactNode;
  eyebrow: string;
  status?: React.ReactNode;
  title: React.ReactNode;
}) {
  return (
    <section className="flex flex-col gap-5 border-b border-[#d8d0c2] pb-7 lg:flex-row lg:items-end lg:justify-between">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-3">
          <p className="page-eyebrow">{eyebrow}</p>
          {status}
        </div>
        <h1 className="page-title">{title}</h1>
        <div className="page-description">{description}</div>
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </section>
  );
}

export function GMSectionNav({ items }: { items: SectionLink[] }) {
  return (
    <nav aria-label="页面分区" className="sticky top-16 z-10 -mx-4 mt-6 overflow-x-auto border-y border-[#d8d0c2] bg-[#f4f0e7]/95 px-4 py-2 backdrop-blur sm:-mx-6 sm:px-6 xl:-mx-8 xl:px-8">
      <div className="mx-auto flex min-w-max gap-1">
        {items.map((item) => (
          <a className="inline-flex min-h-10 items-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold text-[#59635c] hover:bg-[#fffcf6] hover:text-[#173f35]" href={item.href} key={item.href}>
            {item.label}
            {item.count !== undefined && <span className="rounded-full bg-[#ebe5da] px-2 py-0.5 font-mono text-[0.68rem] text-[#735421]">{item.count}</span>}
          </a>
        ))}
      </div>
    </nav>
  );
}

type TaskItem = {
  count: number;
  description: string;
  href: string;
  label: string;
  tone?: "danger" | "neutral" | "success" | "warning";
};

export function GMTaskSummary({ items }: { items: TaskItem[] }) {
  const toneStyles = {
    danger: "border-[#dca9a5] bg-[#f8e4e2] text-[#8f322e]",
    neutral: "border-[#d8d0c2] bg-[#fffcf6] text-[#173f35]",
    success: "border-[#a8cbb8] bg-[#e2f0e8] text-[#246647]",
    warning: "border-[#d7c393] bg-[#f4ead0] text-[#735421]",
  };

  return (
    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {items.map((item) => (
        <Link className={`group rounded-2xl border p-4 shadow-[0_8px_24px_rgb(57_47_31/4%)] hover:-translate-y-0.5 ${toneStyles[item.tone ?? "neutral"]}`} href={item.href} key={item.href + item.label}>
          <div className="flex items-start justify-between gap-3">
            <div><p className="text-sm font-bold">{item.label}</p><p className="mt-1 text-xs leading-5 opacity-75">{item.description}</p></div>
            <span className="font-mono text-2xl font-semibold">{item.count}</span>
          </div>
        </Link>
      ))}
    </div>
  );
}

export function DangerZone({ children, description, title }: { children: React.ReactNode; description: React.ReactNode; title: string }) {
  return (
    <section className="rounded-2xl border border-[#dca9a5] bg-[#fff8f7] p-5 sm:p-6">
      <p className="text-xs font-bold uppercase tracking-[0.18em] text-[#a33d38]">DANGER ZONE</p>
      <h2 className="display-title mt-2 text-xl font-semibold text-[#762a27]">{title}</h2>
      <div className="mt-2 text-sm leading-6 text-[#76514f]">{description}</div>
      <div className="mt-5">{children}</div>
    </section>
  );
}
