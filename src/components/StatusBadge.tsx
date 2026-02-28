import type { AppPhase } from "../context/types";

const config: Record<AppPhase, { label: string; color: string; animate: boolean }> = {
  setup: { label: "", color: "", animate: false },
  idle: { label: "", color: "", animate: false },
  recording: { label: "Recording", color: "bg-red-500", animate: true },
  processing: { label: "Transcribing", color: "bg-yellow-500", animate: true },
  ready: { label: "Ready", color: "bg-green-500", animate: false },
};

export function StatusBadge({ phase }: { phase: AppPhase }) {
  const { label, color, animate } = config[phase];

  if (!label) return null;

  return (
    <div className="flex items-center gap-2">
      <span className="relative flex h-2.5 w-2.5">
        {animate && (
          <span
            className={`absolute inline-flex h-full w-full rounded-full ${color} opacity-75 animate-ping`}
          />
        )}
        <span className={`relative inline-flex rounded-full h-2.5 w-2.5 ${color}`} />
      </span>
      <span className="text-xs text-white/60 uppercase tracking-wider">{label}</span>
    </div>
  );
}
