import { Command } from "@tauri-apps/plugin-shell";
import type { Session } from "../context/types";

interface DispatchOptions {
  prompt: string;
  /** If null, starts a new session. If provided, attaches to existing session. */
  session: Session | null;
}

/**
 * Dispatch a prompt to OpenCode via the live server.
 * Uses `opencode --attach localhost:4096 --session $ID run $PROMPT`
 * for existing sessions, or just `opencode run $PROMPT` for new ones.
 */
export async function dispatchPrompt({ prompt, session }: DispatchOptions): Promise<void> {
  const escaped = prompt.replace(/'/g, "'\\''");

  const shellCmd = session
    ? `opencode --attach localhost:4096 --session '${session.id.replace(/'/g, "'\\''")}' run '${escaped}'`
    : `opencode run '${escaped}'`;

  console.log("Dispatching to opencode:", shellCmd);

  try {
    const command = Command.create("sh", ["-c", shellCmd]);

    command.on("error", (err) => {
      console.error("opencode error:", err);
    });

    const child = await command.spawn();
    console.log("opencode spawned with PID:", child.pid);
  } catch (e) {
    console.error("Failed to spawn opencode:", e);
    throw new Error(`Failed to start opencode: ${e}`);
  }
}
