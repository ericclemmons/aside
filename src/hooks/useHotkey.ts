import { useEffect, useRef } from "react";
import { listen } from "@tauri-apps/api/event";
import { invoke } from "@tauri-apps/api/core";
import { useAppState } from "../context/AppContext";
import { playStartSound, playStopSound } from "../services/activationSound";

/**
 * Listens for global hotkey press/release events from the Rust backend.
 * On press: shows overlay, captures context + starts recording.
 * On release: stops recording + triggers transcription.
 */
export function useHotkey() {
  const { state, dispatch } = useAppState();
  const phaseRef = useRef(state.phase);
  phaseRef.current = state.phase;

  useEffect(() => {
    const unlisteners: Array<() => void> = [];

    async function setup() {
      const unlisten1 = await listen("hotkey-pressed", async () => {
        if (phaseRef.current !== "idle") return;

        // Update ref immediately so release handler can see it
        phaseRef.current = "recording";
        dispatch({ type: "START_RECORDING" });
        invoke("show_overlay");
        playStartSound();

        invoke("start_recording").catch((e) => {
          console.error("Failed to start recording:", e);
          dispatch({ type: "SET_ERROR", error: String(e) });
        });

        invoke<{
          app_name: string;
          window_title: string;
          url: string | null;
          selected_text: string | null;
        }>("get_active_context")
          .then((ctx) => {
            if (ctx) dispatch({ type: "SET_CONTEXT", context: ctx });
          })
          .catch((e) => console.error("Failed to capture context:", e));
      });
      unlisteners.push(unlisten1);

      const unlisten2 = await listen("hotkey-released", async () => {
        if (phaseRef.current !== "recording") return;

        // Update ref immediately to prevent re-entry
        phaseRef.current = "processing";
        dispatch({ type: "STOP_RECORDING" });
        playStopSound();

        try {
          await invoke("stop_recording");
          const result = await invoke<{ text: string; duration_ms: number }>("transcribe_audio");
          if (!result.text.trim()) {
            // Empty transcription — nothing to do, go back to idle
            phaseRef.current = "idle";
            dispatch({ type: "CANCEL" });
            invoke("hide_overlay");
            return;
          }
          phaseRef.current = "ready";
          dispatch({ type: "TRANSCRIPTION_COMPLETE", text: result.text });
        } catch (e) {
          console.error("Transcription failed:", e);
          dispatch({ type: "SET_ERROR", error: String(e) });
          phaseRef.current = "idle";
          dispatch({ type: "CANCEL" });
          invoke("hide_overlay");
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
