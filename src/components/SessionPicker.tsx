import type { Session } from "../context/types";

interface SessionPickerProps {
  sessions: Session[];
  selectedIndex: number; // -1 = "New Session"
}

export function SessionPicker({ sessions, selectedIndex }: SessionPickerProps) {
  return (
    <div className="flex flex-col gap-2">
      <div className="text-[10px] text-white/30 text-center">
        ↑ ↓ select · ⌘Enter send · Esc cancel
      </div>

      {/* Session list */}
      <div className="flex flex-col gap-0.5 max-h-32 overflow-y-auto">
        {/* New Session option */}
        <SessionRow
          label="New Session"
          subtitle="Start a new opencode session"
          isSelected={selectedIndex === -1}
        />

        {sessions.length === 0 && (
          <div className="text-xs text-white/20 text-center py-1">No recent sessions</div>
        )}

        {sessions.map((session, idx) => (
          <SessionRow
            key={session.id}
            label={session.name}
            subtitle={formatRelative(session.lastActive)}
            isSelected={selectedIndex === idx}
          />
        ))}
      </div>
    </div>
  );
}

function formatRelative(dateStr: string): string {
  if (!dateStr) return "";
  try {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMin = Math.floor(diffMs / 60000);
    if (diffMin < 1) return "just now";
    if (diffMin < 60) return `${diffMin}m ago`;
    const diffHr = Math.floor(diffMin / 60);
    if (diffHr < 24) return `${diffHr}h ago`;
    const diffDay = Math.floor(diffHr / 24);
    return `${diffDay}d ago`;
  } catch {
    return dateStr;
  }
}

function SessionRow({
  label,
  subtitle,
  isSelected,
}: {
  label: string;
  subtitle: string;
  isSelected: boolean;
}) {
  return (
    <div
      className={`flex items-center justify-between px-3 py-1.5 rounded-md transition-colors ${
        isSelected
          ? "bg-purple-500/20 border border-purple-500/30"
          : "border border-transparent hover:bg-white/5"
      }`}
    >
      <span className={`text-xs truncate ${isSelected ? "text-white" : "text-white/50"}`}>
        {label}
      </span>
      {subtitle && <span className="text-[10px] text-white/30 ml-2 shrink-0">{subtitle}</span>}
    </div>
  );
}
