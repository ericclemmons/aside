import { useCallback, useEffect } from "react";
import { Command } from "@tauri-apps/plugin-shell";
import { useAppState } from "../context/AppContext";
import type { Session } from "../context/types";

async function fetchSessions(): Promise<Session[]> {
  try {
    const command = Command.create("sh", ["-c", "opencode session list --format json"]);
    const output = await command.execute();

    if (output.code !== 0) {
      console.warn("opencode session list failed:", output.stderr);
      return [];
    }

    const raw = JSON.parse(output.stdout);
    // Expect an array of objects with at least id, and optionally updated_at/title
    const sessions: Session[] = (Array.isArray(raw) ? raw : []).map(
      (s: Record<string, unknown>) => ({
        id: String(s.id ?? ""),
        name: String(s.title ?? s.id ?? "Untitled"),
        lastActive: String(s.updated_at ?? s.created_at ?? ""),
      }),
    );

    // Sort by lastActive descending (most recent first)
    sessions.sort((a, b) => new Date(b.lastActive).getTime() - new Date(a.lastActive).getTime());

    return sessions;
  } catch (e) {
    console.warn("Failed to fetch opencode sessions:", e);
    return [];
  }
}

/**
 * Fetches sessions from OpenCode CLI.
 * Refreshes when the overlay opens (phase transitions to recording).
 */
export function useSessions() {
  const { state, dispatch } = useAppState();

  const refresh = useCallback(async () => {
    const sessions = await fetchSessions();
    dispatch({ type: "SET_SESSIONS", sessions });
  }, [dispatch]);

  // Refresh sessions when recording starts (overlay opens)
  useEffect(() => {
    if (state.phase === "recording") {
      refresh();
    }
  }, [state.phase, refresh]);

  return {
    sessions: state.sessions,
    selectedIndex: state.selectedSessionIndex,
    refresh,
  };
}
