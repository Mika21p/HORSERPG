type NoticeProps = {
  message?: string;
};

export function Notice({ message }: NoticeProps) {
  if (!message) {
    return null;
  }

  return (
    <p aria-live="polite" className="mb-5 rounded-lg border border-amber-300/30 bg-amber-300/10 px-4 py-3 text-sm text-amber-100">
      {message}
    </p>
  );
}
