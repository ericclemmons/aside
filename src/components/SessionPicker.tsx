import type { CliProvider, Session } from "../context/types";

interface SessionPickerProps {
  activeProvider: CliProvider;
  sessions: Session[];
  selectedIndex: number; // -1 = "New Session"
}

const providers: { key: CliProvider; label: string }[] = [
  { key: "claude", label: "Claude" },
  { key: "opencode", label: "OpenCode" },
];

export function SessionPicker({
  activeProvider,
  sessions,
  selectedIndex,
}: SessionPickerProps) {
  return (
    <div className="flex flex-col gap-2">
      {/* Provider tabs */}
      <div className="flex gap-1 bg-white/5 rounded-lg p-0.5">
        {providers.map((p) => (
          <button
            key={p.key}
            className={`flex-1 text-xs py-1.5 rounded-md transition-colors ${
              activeProvider === p.key
                ? "bg-white/15 text-white"
                : "text-white/40 hover:text-white/60"
            }`}
            tabIndex={-1}
          >
            {p.label}
          </button>
        ))}
      </div>

      <div className="text-[10px] text-white/30 text-center">
        ← → switch provider · ↑ ↓ select session · Enter send · Esc cancel
      </div>

      {/* Session list */}
      <div className="flex flex-col gap-0.5 max-h-32 overflow-y-auto">
        {/* New Session option */}
        <SessionRow
          label="New Session"
          subtitle={`Start a new ${activeProvider} session`}
          isSelected={selectedIndex === -1}
        />

        {sessions.length === 0 && (
          <div className="text-xs text-white/20 text-center py-1">
            No recent sessions
          </div>
        )}

        {sessions.map((session, idx) => (
          <SessionRow
            key={session.id}
            label={session.name}
            subtitle={session.lastActive}
            isSelected={selectedIndex === idx}
          />
        ))}
      </div>
    </div>
  );
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
      <span
        className={`text-xs truncate ${
          isSelected ? "text-white" : "text-white/50"
        }`}
      >
        {label}
      </span>
      {subtitle && (
        <span className="text-[10px] text-white/30 ml-2 shrink-0">
          {subtitle}
        </span>
      )}
    </div>
  );
}
