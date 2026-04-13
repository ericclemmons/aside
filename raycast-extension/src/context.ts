import { getSelectedText, getFrontmostApplication, Clipboard, getSelectedFinderItems } from "@raycast/api";
import { runAppleScript } from "@raycast/utils";
import { readdirSync, statSync } from "fs";
import { join } from "path";
import { getPreferenceValues } from "@raycast/api";

export interface ContextItem {
  type: "selectedText" | "url" | "screenshot" | "clipboard";
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
 * Selected text is deduped against clipboard (Raycast's getSelectedText
 * sometimes returns clipboard contents when nothing is actually selected).
 */
export interface GatheredContext {
  items: ContextItem[];
  /** File paths auto-detected (Finder selection + recent screenshots) */
  files: string[];
}

export async function gatherContext(): Promise<GatheredContext> {
  const items: ContextItem[] = [];
  const files: string[] = [];

  // Read clipboard first so we can dedupe selected text against it
  const clipboardText = await Clipboard.readText().catch(() => undefined);

  // Check for Finder-selected files first — if present, skip getSelectedText
  // (Finder reports the filename as "selected text" which is noise)
  const finderFiles = await captureSelectedFinderFiles();
  const hasFinderFiles = finderFiles.length > 0;

  const results = await Promise.allSettled([
    hasFinderFiles ? null : captureSelectedText(clipboardText),
    captureClipboardText(clipboardText),
    captureBrowserURL(),
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

  // Extract auto-enabled screenshots as files for the file picker
  const screenshotFiles = items
    .filter((item) => item.type === "screenshot" && item.defaultEnabled)
    .map((item) => item.value);
  // Remove screenshots from items — they go in the file picker
  const textItems = items.filter((item) => item.type !== "screenshot");

  // Add Finder-selected files
  files.push(...finderFiles.map((f) => f.value));

  files.push(...screenshotFiles);

  return { items: textItems, files: [...new Set(files)] };
}

async function captureSelectedFinderFiles(): Promise<ContextItem[]> {
  try {
    const finderItems = await getSelectedFinderItems();
    return finderItems.map((item) => ({
      type: "screenshot" as const, // reuse type for file paths
      label: item.path.split("/").pop() || item.path,
      value: item.path,
      defaultEnabled: true,
    }));
  } catch {
    return [];
  }
}

async function captureSelectedText(clipboardText: string | undefined): Promise<ContextItem | null> {
  try {
    const text = await getSelectedText();
    if (!text || text.trim().length === 0) return null;
    // Dedupe: if "selected text" is identical to clipboard, it's not actually selected
    if (clipboardText && text === clipboardText) return null;

    const preview = text.length > 80 ? text.slice(0, 80) + "…" : text;
    return {
      type: "selectedText",
      label: preview,
      value: text,
      defaultEnabled: true,
    };
  } catch {
    return null;
  }
}

async function captureClipboardText(clipboardText: string | undefined): Promise<ContextItem | null> {
  if (!clipboardText || clipboardText.trim().length === 0) return null;
  const preview = clipboardText.length > 80 ? clipboardText.slice(0, 80) + "…" : clipboardText;
  return {
    type: "clipboard",
    label: preview,
    value: clipboardText,
    defaultEnabled: false,
  };
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
      case "Dia":
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
        label: url,
        value: url,
        defaultEnabled: true,
      };
    }
  } catch {
    // Not a browser or no URL — not an error
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

    const oneMinuteMs = 60 * 1000;
    for (const s of screenshots) {
      const ago = Math.floor((now - s.mtime) / 1000);
      const agoStr = ago < 60 ? `${ago}s ago` : `${Math.floor(ago / 60)}m ago`;
      items.push({
        type: "screenshot",
        label: `Screenshot · ${agoStr}`,
        value: s.path,
        defaultEnabled: (now - s.mtime) < oneMinuteMs,
      });
    }
  } catch {
    // Directory doesn't exist or isn't readable
  }

  return items;
}

/**
 * Build a prompt string with context as blockquoted preamble.
 */
export function buildPrompt(text: string, contextItems: ContextItem[]): string {
  const quoted: string[] = [];

  for (const item of contextItems) {
    if (item.type === "screenshot") continue; // attached as files, not inline
    if (item.type === "url") {
      quoted.push(`> ${item.value}`);
    } else {
      // selectedText and clipboard both inline as blockquote
      const lines = item.value.split("\n").map((line) => `> ${line}`);
      quoted.push(lines.join("\n"));
    }
  }

  if (quoted.length === 0) return text;
  return quoted.join("\n") + "\n\n" + text;
}
