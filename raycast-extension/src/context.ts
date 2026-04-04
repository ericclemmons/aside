import { getSelectedText, getFrontmostApplication, Clipboard } from "@raycast/api";
import { runAppleScript } from "@raycast/utils";
import { readdirSync, statSync } from "fs";
import { join } from "path";
import { getPreferenceValues } from "@raycast/api";

export interface ContextItem {
  type: "selectedText" | "url" | "clipboard" | "screenshot";
  label: string;
  value: string;
  /** Whether this item is checked by default */
  defaultEnabled: boolean;
}

interface Preferences {
  screenshotDir?: string;
  screenshotMaxAge?: string;
}

/**
 * Gather all context items from the environment.
 * Each source is independent — failures are silently skipped.
 */
export async function gatherContext(): Promise<ContextItem[]> {
  const items: ContextItem[] = [];

  const results = await Promise.allSettled([
    captureSelectedText(),
    captureBrowserURL(),
    captureClipboard(),
    captureRecentScreenshots(),
  ]);

  for (const result of results) {
    if (result.status === "fulfilled" && result.value) {
      if (Array.isArray(result.value)) {
        items.push(...result.value);
      } else {
        items.push(result.value);
      }
    }
  }

  return items;
}

async function captureSelectedText(): Promise<ContextItem | null> {
  try {
    const text = await getSelectedText();
    if (text && text.trim().length > 0) {
      const preview = text.length > 80 ? text.slice(0, 80) + "..." : text;
      return {
        type: "selectedText",
        label: `Selected text: "${preview}"`,
        value: text,
        defaultEnabled: true,
      };
    }
  } catch {
    // No text selected — not an error
  }
  return null;
}

async function captureBrowserURL(): Promise<ContextItem | null> {
  try {
    const app = await getFrontmostApplication();
    const appName = app.name;

    let script: string;
    switch (appName) {
      case "Google Chrome":
      case "Brave Browser":
      case "Microsoft Edge":
      case "Chromium":
      case "Arc":
        script = `tell application "${appName}" to return URL of active tab of front window`;
        break;
      case "Safari":
      case "Safari Technology Preview":
        script = `tell application "${appName}" to return URL of front document`;
        break;
      default:
        return null;
    }

    const url = await runAppleScript(script);
    if (url && url.trim().length > 0 && url !== "missing value") {
      return {
        type: "url",
        label: `URL: ${url}`,
        value: url,
        defaultEnabled: true,
      };
    }
  } catch {
    // Not a browser or no URL — not an error
  }
  return null;
}

async function captureClipboard(): Promise<ContextItem | null> {
  try {
    const text = await Clipboard.readText();
    if (text && text.trim().length > 0) {
      const preview = text.length > 80 ? text.slice(0, 80) + "..." : text;
      return {
        type: "clipboard",
        label: `Clipboard: "${preview}"`,
        value: text,
        defaultEnabled: false,
      };
    }
  } catch {
    // Clipboard empty or inaccessible
  }
  return null;
}

async function captureRecentScreenshots(): Promise<ContextItem[]> {
  const prefs = getPreferenceValues<Preferences>();
  const screenshotDir = (prefs.screenshotDir || "~/Desktop").replace("~", process.env.HOME || "");
  const maxAgeMinutes = parseInt(prefs.screenshotMaxAge || "5", 10);
  const maxAgeMs = maxAgeMinutes * 60 * 1000;
  const now = Date.now();

  const items: ContextItem[] = [];

  try {
    const files = readdirSync(screenshotDir);
    const screenshots = files
      .filter((f) => /^Screenshot.*\.(png|jpg|jpeg|tiff)$/i.test(f))
      .map((f) => {
        const fullPath = join(screenshotDir, f);
        const stat = statSync(fullPath);
        return { name: f, path: fullPath, mtime: stat.mtimeMs };
      })
      .filter((f) => now - f.mtime < maxAgeMs)
      .sort((a, b) => b.mtime - a.mtime)
      .slice(0, 5);

    for (const s of screenshots) {
      const ago = Math.floor((now - s.mtime) / 1000);
      const agoStr = ago < 60 ? `${ago}s ago` : `${Math.floor(ago / 60)}m ago`;
      items.push({
        type: "screenshot",
        label: `Screenshot (${agoStr}): ${s.name}`,
        value: s.path,
        defaultEnabled: false,
      });
    }
  } catch {
    // Directory doesn't exist or isn't readable
  }

  return items;
}

/**
 * Build a prompt string with context, matching PromptBuilder.swift format.
 */
export function buildPrompt(text: string, contextItems: ContextItem[]): string {
  const parts: string[] = [];

  const selectedText = contextItems.find((c) => c.type === "selectedText");
  if (selectedText) {
    const truncated = selectedText.value.length > 500 ? selectedText.value.slice(0, 500) + "..." : selectedText.value;
    const quoted = truncated
      .split("\n")
      .map((line) => `> ${line}`)
      .join("\n");
    parts.push(quoted);
  }

  const url = contextItems.find((c) => c.type === "url");
  if (url) {
    parts.push(`> - ${url.value}`);
  }

  const clipboard = contextItems.find((c) => c.type === "clipboard");
  if (clipboard) {
    const truncated = clipboard.value.length > 300 ? clipboard.value.slice(0, 300) + "..." : clipboard.value;
    const quoted = truncated
      .split("\n")
      .map((line) => `> ${line}`)
      .join("\n");
    parts.push(quoted);
  }

  if (parts.length > 0) {
    parts.push("");
  }

  parts.push(text);

  return parts.join("\n");
}
