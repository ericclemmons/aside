import { useAppState } from "../context/AppContext";

/**
 * Provides the active window context captured when the hotkey was pressed.
 * The actual capture happens in useHotkey — this hook just reads the state.
 */
export function useActiveContext() {
  const { state } = useAppState();
  return state.activeContext;
}
