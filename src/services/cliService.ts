import { Command } from "@tauri-apps/plugin-shell";
import type { CliProvider, Session } from "../context/types";

interface DispatchOptions {
  provider: CliProvider;
  prompt: string;
  /** If null, starts a new session. If provided, continues an existing session. */
  session: Session | null;
}

/**
 * Dispatch a prompt to Claude or OpenCode CLI.
 * Spawns the process in the background — we don't wait for the response.
 */
export async function dispatchPrompt({
  provider,
  prompt,
  session,
}: DispatchOptions): Promise<void> {
  const cmd = provider === "claude" ? "claude" : "opencode";

  const args: string[] = [];

  if (session) {
    // Continue existing session
    args.push("--continue", "--print", prompt);
  } else {
    // New session
    args.push("--print", prompt);
  }

  console.log(`Dispatching to ${cmd}:`, args);

  try {
    const command = Command.create(cmd, args);

    // Spawn in background — we don't block on the result
    const child = await command.spawn();
    console.log(`${cmd} spawned with PID:`, child.pid);
  } catch (e) {
    console.error(`Failed to spawn ${cmd}:`, e);
    throw new Error(`Failed to start ${cmd}: ${e}`);
  }
}
