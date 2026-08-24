type NoticeProps = {
  message?: string;
};

export function Notice({ message }: NoticeProps) {
  if (!message) {
    return null;
  }

  return (
    <p aria-live="polite" className="mb-5 rounded-xl border border-[#d7c393] bg-[#f4ead0] px-4 py-3 text-sm text-[#735421] shadow-[0_6px_18px_rgb(57_47_31/5%)]">
      {message}
    </p>
  );
}
