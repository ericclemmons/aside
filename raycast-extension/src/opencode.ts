import { execSync, execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

export interface DiscoveredServer {
  host: string;
  port: number;
  username: string;
  password: string;
  cliPath: string;
  attachTarget: string;
}

export interface Session {
  id: string;
  name: string;
  updatedAt: Date;
  directory?: string;
}

/**
 * Discover a running OpenCode Desktop server by scanning process list.
 * Mirrors the logic in bin/aside's discover_server().
 */
export function discoverServer(): DiscoveredServer | null {
  let psOutput: string;
  try {
    psOutput = execSync("ps ewwA -o pid,command", { encoding: "utf-8", maxBuffer: 10 * 1024 * 1024 });
  } catch {
    return null;
  }

  for (const line of psOutput.split("\n")) {
    if (!line.includes("OpenCode.app") || !line.includes("opencode-cli") || !line.includes("serve")) continue;
    if (line.includes("grep")) continue;

    const portMatch = line.match(/--port[= ](\d+)/);
    if (!portMatch) continue;
    const port = parseInt(portMatch[1], 10);

    const hostMatch = line.match(/--hostname[= ](\S+)/);
    const host = hostMatch ? hostMatch[1] : "127.0.0.1";

    const userMatch = line.match(/OPENCODE_SERVER_USERNAME=(\S+)/);
    const username = userMatch ? userMatch[1] : "opencode";

    const passMatch = line.match(/OPENCODE_SERVER_PASSWORD=(\S+)/);
    if (!passMatch) continue;
    const password = passMatch[1];

    const cliMatch = line.match(/\/[^ ]*opencode-cli/);
    const cliPath = cliMatch ? cliMatch[0] : "";

    return {
      host,
      port,
      username,
      password,
      cliPath,
      attachTarget: `http://${host}:${port}`,
    };
  }

  return null;
}

/**
 * Fetch sessions from the OpenCode server.
 */
export async function fetchSessions(server: DiscoveredServer): Promise<Session[]> {
  const url = `${server.attachTarget}/session`;
  const headers: Record<string, string> = {};

  if (server.username && server.password) {
    const encoded = Buffer.from(`${server.username}:${server.password}`).toString("base64");
    headers["Authorization"] = `Basic ${encoded}`;
  }

  const response = await fetch(url, { headers });
  if (!response.ok) return [];

  const json = (await response.json()) as Array<Record<string, unknown>>;

  const sessions: Session[] = [];
  for (const obj of json) {
    const id = obj.id as string;
    if (!id) continue;

    const time = obj.time as Record<string, unknown> | undefined;
    if (time?.archived != null) continue;

    const name = (obj.title as string) || id;
    const updatedMs = ((time?.updated as number) || (time?.created as number) || 0);
    const updatedAt = new Date(updatedMs);
    const directory = obj.directory as string | undefined;

    sessions.push({ id, name, updatedAt, directory });
  }

  sessions.sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
  return sessions;
}

/**
 * Fetch the current project directory from the OpenCode server.
 */
export async function fetchProjectDirectory(server: DiscoveredServer): Promise<string | null> {
  const url = `${server.attachTarget}/project/current`;
  const headers: Record<string, string> = {};

  if (server.username && server.password) {
    const encoded = Buffer.from(`${server.username}:${server.password}`).toString("base64");
    headers["Authorization"] = `Basic ${encoded}`;
  }

  try {
    const response = await fetch(url, { headers });
    if (!response.ok) return null;
    const json = (await response.json()) as Record<string, unknown>;
    const path = json.path as string;
    return path || null;
  } catch {
    return null;
  }
}

/**
 * Dispatch a prompt to OpenCode via the CLI.
 */
export async function dispatch(opts: {
  prompt: string;
  server: DiscoveredServer;
  sessionId?: string;
  filePaths?: string[];
  workingDirectory?: string;
}): Promise<{ success: boolean; error?: string }> {
  const { prompt, server, sessionId, filePaths = [], workingDirectory } = opts;
  const home = process.env.HOME || `/Users/${process.env.USER}`;
  const opencodePath = server.cliPath || `${home}/.opencode/bin/opencode`;

  const args: string[] = ["--attach", server.attachTarget];

  if (sessionId) {
    args.push("--session", sessionId);
  }

  if (workingDirectory) {
    args.push("--dir", workingDirectory);
  }

  args.push("run");

  for (const path of filePaths) {
    args.push(`--file=${path}`);
  }

  args.push("--");
  args.push(...prompt.split(/\s+/).filter(Boolean));

  const env: Record<string, string> = { ...process.env } as Record<string, string>;
  env.PATH = `${home}/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:${env.PATH || ""}`;

  if (server.username) {
    env.OPENCODE_SERVER_USERNAME = server.username;
  }
  if (server.password) {
    env.OPENCODE_SERVER_PASSWORD = server.password;
  }

  try {
    await execFileAsync(opencodePath, args, {
      env,
      cwd: workingDirectory || undefined,
      timeout: 30000,
    });
    return { success: true };
  } catch (err: unknown) {
    const error = err as Error & { stderr?: string };
    return { success: false, error: error.stderr || error.message };
  }
}

/**
 * Relative time string: "2m ago", "3h ago", etc.
 */
export function timeAgo(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return "now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
  return `${Math.floor(seconds / 604800)}w ago`;
}

/**
 * Replace home directory with ~ for display.
 */
export function abbreviateHome(path: string): string {
  const home = process.env.HOME || "";
  if (path === home) return "~";
  if (path.startsWith(home + "/")) return "~" + path.slice(home.length);
  return path;
}
