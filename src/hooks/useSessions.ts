import { useCallback, useEffect } from "react";
import { Command } from "@tauri-apps/plugin-shell";
import { useAppState } from "../context/AppContext";
import type { CliProvider, Session } from "../context/types";

/**
 * Parse session list output from Claude or OpenCode CLI.
 * Expected format varies — we do best-effort parsing.
 */
function parseSessionLines(output: string): Session[] {
  const sessions: Session[] = [];
  const lines = output.trim().split("\n").filter(Boolean);

  for (const line of lines) {
    // Try to parse lines like: "session-id  Session Name  2024-01-15T10:30:00Z"
    // This is best-effort — actual format depends on CLI version
    const parts = line.trim().split(/\s{2,}/);
    if (parts.length >= 2) {
      sessions.push({
        id: parts[0],
        name: parts[1] || parts[0],
        lastActive: parts[2] || "",
      });
    }
  }

  return sessions;
}

async function fetchSessions(provider: CliProvider): Promise<Session[]> {
  try {
    const cmd = provider === "claude" ? "claude" : "opencode";
    const command = Command.create(cmd, ["sessions", "list"]);
    const output = await command.execute();

    if (output.code !== 0) {
      console.warn(`${cmd} sessions list failed:`, output.stderr);
      return [];
    }

    return parseSessionLines(output.stdout);
  } catch (e) {
    console.warn(`Failed to fetch ${provider} sessions:`, e);
    return [];
  }
}

/**
 * Fetches sessions from both Claude and OpenCode CLIs.
 * Refreshes when the overlay opens (phase transitions to recording).
 */
export function useSessions() {
  const { state, dispatch } = useAppState();

  const refresh = useCallback(async () => {
    const [claudeSessions, opencodeSessions] = await Promise.all([
      fetchSessions("claude"),
      fetchSessions("opencode"),
    ]);

    dispatch({ type: "SET_SESSIONS", provider: "claude", sessions: claudeSessions });
    dispatch({ type: "SET_SESSIONS", provider: "opencode", sessions: opencodeSessions });
  }, [dispatch]);

  // Refresh sessions when recording starts (overlay opens)
  useEffect(() => {
    if (state.phase === "recording") {
      refresh();
    }
  }, [state.phase, refresh]);

  return {
    sessions: state.sessions[state.activeProvider],
    activeProvider: state.activeProvider,
    selectedIndex: state.selectedSessionIndex,
    refresh,
  };
}
