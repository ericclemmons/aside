import { execSync, execFile } from "child_process";
import { promisify } from "util";

const execFileAsync = promisify(execFile);

export interface DiscoveredServer {
  host: string;
  port: number;
  username: string;
  password: string;
  cliPath: string;
}

export interface Session {
  id: string;
  name: string;
  updatedAt: Date;
  directory?: string;
}

function baseURL(server: DiscoveredServer): string {
  return `http://${server.host}:${server.port}`;
}

function authHeaders(server: DiscoveredServer): Record<string, string> {
  if (!server.username || !server.password) return {};
  const encoded = Buffer.from(`${server.username}:${server.password}`).toString("base64");
  return { Authorization: `Basic ${encoded}` };
}

/**
 * Discover a running OpenCode Desktop server by scanning process list.
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

    const passMatch = line.match(/OPENCODE_SERVER_PASSWORD=(\S+)/);
    if (!passMatch) continue;

    const hostMatch = line.match(/--hostname[= ](\S+)/);
    const userMatch = line.match(/OPENCODE_SERVER_USERNAME=(\S+)/);
    const cliMatch = line.match(/\/[^ ]*opencode-cli/);

    return {
      host: hostMatch?.[1] ?? "127.0.0.1",
      port: parseInt(portMatch[1], 10),
      username: userMatch?.[1] ?? "opencode",
      password: passMatch[1],
      cliPath: cliMatch?.[0] ?? "",
    };
  }

  return null;
}

export async function fetchSessions(server: DiscoveredServer): Promise<Session[]> {
  const response = await fetch(`${baseURL(server)}/session`, { headers: authHeaders(server) });
  if (!response.ok) return [];

  const json = (await response.json()) as Array<Record<string, unknown>>;

  return json
    .filter((obj) => obj.id && !(obj.time as Record<string, unknown>)?.archived)
    .map((obj) => {
      const time = obj.time as Record<string, unknown> | undefined;
      return {
        id: obj.id as string,
        name: (obj.title as string) || (obj.id as string),
        updatedAt: new Date(((time?.updated as number) || (time?.created as number) || 0)),
        directory: obj.directory as string | undefined,
      };
    })
    .sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime());
}

export async function fetchProjectDirectory(server: DiscoveredServer): Promise<string | null> {
  try {
    const response = await fetch(`${baseURL(server)}/project/current`, { headers: authHeaders(server) });
    if (!response.ok) return null;
    const json = (await response.json()) as Record<string, unknown>;
    return (json.path as string) || null;
  } catch {
    return null;
  }
}

/**
 * Dispatch a prompt to OpenCode via the CLI.
 * The prompt is passed as a single argument after `--`.
 */
export async function dispatch(opts: {
  prompt: string;
  server: DiscoveredServer;
  sessionId?: string;
  filePaths?: string[];
  workingDirectory?: string;
}): Promise<{ success: boolean; error?: string }> {
  const { prompt, server, sessionId, filePaths = [], workingDirectory } = opts;
  const home = process.env.HOME ?? "";
  const opencodePath = server.cliPath || `${home}/.opencode/bin/opencode`;

  const args: string[] = ["--attach", baseURL(server)];
  if (sessionId) args.push("--session", sessionId);
  if (workingDirectory) args.push("--dir", workingDirectory);

  args.push("run");
  for (const path of filePaths) args.push(`--file=${path}`);
  args.push("--", ...prompt.split(/\s+/).filter(Boolean));

  const env: Record<string, string> = { ...process.env } as Record<string, string>;
  env.PATH = `${home}/.opencode/bin:/opt/homebrew/bin:/usr/local/bin:${env.PATH || ""}`;
  if (server.username) env.OPENCODE_SERVER_USERNAME = server.username;
  if (server.password) env.OPENCODE_SERVER_PASSWORD = server.password;

  console.log("[dispatch]", opencodePath, args.join(" "));

  try {
    const { stderr } = await execFileAsync(opencodePath, args, {
      env,
      cwd: workingDirectory || undefined,
      timeout: 30000,
    });
    if (stderr?.trim()) {
      console.error("[dispatch] stderr:", stderr.trim());
    }
    return { success: true };
  } catch (err: unknown) {
    const error = err as Error & { stderr?: string; stdout?: string };
    const detail = error.stderr?.trim() || error.stdout?.trim() || error.message;
    console.error("[dispatch] failed:", detail);
    return { success: false, error: detail };
  }
}

export function timeAgo(date: Date): string {
  const seconds = Math.floor((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return "now";
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d ago`;
  return `${Math.floor(seconds / 604800)}w ago`;
}

export function abbreviateHome(path: string): string {
  const home = process.env.HOME || "";
  if (path === home) return "~";
  if (path.startsWith(home + "/")) return "~" + path.slice(home.length);
  return path;
}
