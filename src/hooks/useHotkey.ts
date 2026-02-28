import { useEffect, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { useAppState } from "../context/AppContext";

/**
 * Listens for global hotkey press/release events from the Rust backend.
 * On press: captures context + starts recording.
 * On release: stops recording + triggers transcription.
 */
export function useHotkey() {
  const { state, dispatch } = useAppState();
  const phaseRef = useRef(state.phase);
  phaseRef.current = state.phase;

  useEffect(() => {
    const unlisteners: Array<() => void> = [];

    async function setup() {
      // Hotkey pressed — start recording + capture context
      const unlisten1 = await listen("hotkey-pressed", async () => {
        if (phaseRef.current !== "idle") return;

        dispatch({ type: "START_RECORDING" });

        // Capture active window context before overlay takes focus
        try {
          const ctx = await invoke<{
            app_name: string;
            window_title: string;
            url: string | null;
            selected_text: string | null;
          }>("get_active_context");
          dispatch({ type: "SET_CONTEXT", context: ctx });
        } catch (e) {
          console.error("Failed to capture context:", e);
        }

        // Start audio recording
        try {
          await invoke("start_recording");
        } catch (e) {
          console.error("Failed to start recording:", e);
          dispatch({ type: "SET_ERROR", error: String(e) });
        }
      });
      unlisteners.push(unlisten1);

      // Hotkey released — stop recording + transcribe
      const unlisten2 = await listen("hotkey-released", async () => {
        if (phaseRef.current !== "recording") return;

        dispatch({ type: "STOP_RECORDING" });

        try {
          await invoke("stop_recording");
          const result = await invoke<{ text: string; duration_ms: number }>(
            "transcribe_audio"
          );
          dispatch({ type: "TRANSCRIPTION_COMPLETE", text: result.text });
        } catch (e) {
          console.error("Transcription failed:", e);
          dispatch({ type: "SET_ERROR", error: String(e) });
          dispatch({ type: "CANCEL" });
        }
      });
      unlisteners.push(unlisten2);
    }

    setup();

    return () => {
      unlisteners.forEach((fn) => fn());
    };
  }, [dispatch]);
}
