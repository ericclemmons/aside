import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useAppState } from "../context/AppContext";

/**
 * Handles keyboard navigation in the overlay when in "ready" phase:
 * - Up/Down: navigate session list
 * - Cmd+Enter: dispatch prompt
 * - Escape: cancel
 */
export function useOverlayKeyboard(onDispatch: () => void) {
  const { state, dispatch } = useAppState();

  useEffect(() => {
    if (state.phase !== "ready") return;

    function handleKeyDown(e: KeyboardEvent) {
      const maxIndex = state.sessions.length - 1;

      switch (e.key) {
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
          if (e.metaKey) {
            e.preventDefault();
            onDispatch();
          }
          break;
        }

        case "Escape": {
          e.preventDefault();
          dispatch({ type: "CANCEL" });
          invoke("hide_overlay");
          break;
        }
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [state.phase, state.selectedSessionIndex, state.sessions, dispatch, onDispatch]);
}
