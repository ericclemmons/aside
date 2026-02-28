import { useEffect } from "react";
import { listen } from "@tauri-apps/api/event";
import { useAppState } from "../context/AppContext";

/**
 * Subscribes to audio-level events emitted by the Rust audio capture
 * at ~30fps. Pushes amplitude values into state for the Waveform component.
 */
export function useAudioStream() {
  const { dispatch } = useAppState();

  useEffect(() => {
    let unlisten: (() => void) | undefined;

    listen<number>("audio-level", (event) => {
      if (event.payload > 0.001) {
        console.log("[audio-level]", event.payload.toFixed(4));
      }
      dispatch({ type: "PUSH_AUDIO_LEVEL", level: event.payload });
    }).then((fn) => {
      unlisten = fn;
    });

    return () => {
      unlisten?.();
    };
  }, [dispatch]);
}
