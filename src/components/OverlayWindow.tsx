import { useCallback, useEffect, useRef } from "react";
import { invoke } from "@tauri-apps/api/core";
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
import { SetupScreen } from "./SetupScreen";

const OVERLAY_WIDTH = 420;

export function OverlayWindow() {
  const { state, dispatch } = useAppState();
  const rootRef = useRef<HTMLDivElement>(null);

  // Auto-resize window to fit content (skip when idle/empty to avoid ghost window)
  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const observer = new ResizeObserver(() => {
      const height = Math.ceil(el.scrollHeight);
      if (height > 10) {
        invoke("resize_overlay", { width: OVERLAY_WIDTH, height: height + 2 });
      }
    });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // Set up event listeners
  useHotkey();
  useAudioStream();
  const { sessions, selectedIndex } = useSessions();

  const handleDispatch = useCallback(async () => {
    if (!state.transcription.trim()) return;

    const prompt = buildPrompt(state.transcription, state.activeContext);
    const session =
      state.selectedSessionIndex >= 0 ? state.sessions[state.selectedSessionIndex] : null;

    try {
      await dispatchPrompt({
        prompt,
        session: session ?? null,
      });
    } catch (e) {
      console.error("Dispatch failed:", e);
    }

    dispatch({ type: "DISPATCH" });
    invoke("hide_overlay");
  }, [
    state.transcription,
    state.activeContext,
    state.selectedSessionIndex,
    state.sessions,
    dispatch,
  ]);

  useOverlayKeyboard(handleDispatch);

  // Close overlay when window loses focus (click outside).
  // Only dismiss in "ready" phase — don't interrupt recording or processing.
  useEffect(() => {
    const ac = new AbortController();
    let blurTimer: ReturnType<typeof setTimeout>;
    window.addEventListener(
      "blur",
      () => {
        blurTimer = setTimeout(() => {
          if (state.phase === "ready") {
            dispatch({ type: "CANCEL" });
            invoke("hide_overlay");
          }
        }, 300);
      },
      { signal: ac.signal },
    );
    window.addEventListener("focus", () => clearTimeout(blurTimer), { signal: ac.signal });
    return () => {
      clearTimeout(blurTimer);
      ac.abort();
    };
  }, [state.phase, dispatch]);

  // Hide overlay when idle (safety net)
  useEffect(() => {
    if (state.phase === "idle") {
      invoke("hide_overlay");
    }
  }, [state.phase]);

  // Setup screen on first launch
  if (state.phase === "setup") {
    return (
      <div ref={rootRef}>
        <SetupScreen />
      </div>
    );
  }

  // Don't render anything when idle
  if (state.phase === "idle") {
    return <div ref={rootRef} />;
  }

  return (
    <div ref={rootRef} className="w-full flex flex-col gap-3 p-4" data-tauri-drag-region>
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
        <>
          <Waveform levels={state.audioLevels} isActive={state.phase === "recording"} />
          <div className="text-[10px] font-mono text-white/50 text-center">
            mic:{" "}
            {state.audioLevels.length > 0
              ? state.audioLevels[state.audioLevels.length - 1].toFixed(6)
              : "no data"}{" "}
            ({state.audioLevels.length} samples)
          </div>
        </>
      )}

      {/* Transcription */}
      <TranscriptionBox
        text={state.transcription}
        onChange={(text) => dispatch({ type: "SET_TRANSCRIPTION", text })}
        isProcessing={state.phase === "processing"}
      />

      {/* Session picker (only when ready) */}
      {state.phase === "ready" && state.transcription && (
        <SessionPicker sessions={sessions} selectedIndex={selectedIndex} />
      )}

      {/* Error display */}
      {state.error && (
        <div className="text-xs text-red-400 bg-red-500/10 rounded px-2 py-1">{state.error}</div>
      )}
    </div>
  );
}
