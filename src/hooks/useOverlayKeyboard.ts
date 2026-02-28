import { useEffect } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useAppState } from "../context/AppContext";
import type { CliProvider } from "../context/types";

/**
 * Handles keyboard navigation in the overlay when in "ready" phase:
 * - Left/Right: switch between Claude and OpenCode tabs
 * - Up/Down: navigate session list
 * - Enter: dispatch prompt
 * - Escape: cancel
 */
export function useOverlayKeyboard(onDispatch: () => void) {
  const { state, dispatch } = useAppState();

  useEffect(() => {
    if (state.phase !== "ready") return;

    function handleKeyDown(e: KeyboardEvent) {
      const sessions = state.sessions[state.activeProvider];
      const maxIndex = sessions.length - 1; // -1 = New Session, 0..N = existing

      switch (e.key) {
        case "ArrowLeft":
        case "ArrowRight": {
          e.preventDefault();
          const providers: CliProvider[] = ["claude", "opencode"];
          const currentIdx = providers.indexOf(state.activeProvider);
          const nextIdx = e.key === "ArrowRight"
            ? (currentIdx + 1) % providers.length
            : (currentIdx - 1 + providers.length) % providers.length;
          dispatch({ type: "SET_PROVIDER", provider: providers[nextIdx] });
          break;
        }

        case "ArrowDown": {
          e.preventDefault();
          const next = Math.min(state.selectedSessionIndex + 1, maxIndex);
          dispatch({ type: "SET_SESSION_INDEX", index: next });
          break;
        }

        case "ArrowUp": {
          e.preventDefault();
          const prev = Math.max(state.selectedSessionIndex - 1, -1);
          dispatch({ type: "SET_SESSION_INDEX", index: prev });
          break;
        }

        case "Enter": {
          e.preventDefault();
          onDispatch();
          break;
        }

        case "Escape": {
          e.preventDefault();
          dispatch({ type: "CANCEL" });
          getCurrentWindow().hide();
          break;
        }
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [state.phase, state.activeProvider, state.selectedSessionIndex, state.sessions, dispatch, onDispatch]);
}
