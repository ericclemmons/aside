import { useCallback } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useAppState } from "../context/AppContext";
import { useHotkey } from "../hooks/useHotkey";
import { useAudioStream } from "../hooks/useAudioStream";
import { useSessions } from "../hooks/useSessions";
import { useOverlayKeyboard } from "../hooks/useOverlayKeyboard";
import { buildPrompt } from "../services/promptBuilder";
import { dispatchPrompt } from "../services/cliService";
import { Waveform } from "./Waveform";
import { TranscriptionBox } from "./TranscriptionBox";
import { SessionPicker } from "./SessionPicker";
import { StatusBadge } from "./StatusBadge";

export function OverlayWindow() {
  const { state, dispatch } = useAppState();

  // Set up event listeners
  useHotkey();
  useAudioStream();
  const { sessions, activeProvider, selectedIndex } = useSessions();

  const handleDispatch = useCallback(async () => {
    if (!state.transcription.trim()) return;

    const prompt = buildPrompt(state.transcription, state.activeContext);
    const session =
      state.selectedSessionIndex >= 0
        ? state.sessions[state.activeProvider][state.selectedSessionIndex]
        : null;

    try {
      await dispatchPrompt({
        provider: state.activeProvider,
        prompt,
        session: session ?? null,
      });
    } catch (e) {
      console.error("Dispatch failed:", e);
    }

    dispatch({ type: "DISPATCH" });
    getCurrentWindow().hide();
  }, [state.transcription, state.activeContext, state.activeProvider, state.selectedSessionIndex, state.sessions, dispatch]);

  useOverlayKeyboard(handleDispatch);

  // Don't render anything when idle
  if (state.phase === "idle") {
    return <div className="w-full h-full" />;
  }

  return (
    <div className="w-full h-full flex items-center justify-center p-4" data-tauri-drag-region>
      <div className="w-full max-w-[400px] bg-black/80 backdrop-blur-xl rounded-2xl border border-white/10 shadow-2xl overflow-hidden">
        <div className="flex flex-col gap-3 p-4">
          {/* Header: status + context */}
          <div className="flex items-center justify-between">
            <StatusBadge phase={state.phase} />

            {state.activeContext?.app_name && (
              <span className="text-[10px] text-white/30 truncate max-w-[200px]">
                {state.activeContext.url
                  ? `${state.activeContext.app_name} — ${new URL(state.activeContext.url).hostname}`
                  : state.activeContext.app_name}
              </span>
            )}
          </div>

          {/* Waveform */}
          {(state.phase === "recording" || state.phase === "processing") && (
            <Waveform
              levels={state.audioLevels}
              isActive={state.phase === "recording"}
            />
          )}

          {/* Transcription */}
          <TranscriptionBox
            text={state.transcription}
            onChange={(text) =>
              dispatch({ type: "SET_TRANSCRIPTION", text })
            }
            isProcessing={state.phase === "processing"}
          />

          {/* Session picker (only when ready) */}
          {state.phase === "ready" && state.transcription && (
            <SessionPicker
              activeProvider={activeProvider}
              sessions={sessions}
              selectedIndex={selectedIndex}
            />
          )}

          {/* Error display */}
          {state.error && (
            <div className="text-xs text-red-400 bg-red-500/10 rounded px-2 py-1">
              {state.error}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
