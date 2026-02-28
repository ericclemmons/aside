import type { ActiveContext } from "../context/types";

/**
 * Build a prompt string from the user's transcription and captured context.
 *
 * Example output:
 *   [Context: Chrome — https://github.com/org/repo/issues/42]
 *   [Selected: "TypeError: Cannot read property 'map' of undefined"]
 *
 *   Fix this bug
 */
export function buildPrompt(transcription: string, context: ActiveContext | null): string {
  const parts: string[] = [];

  if (context) {
    const appInfo = context.url ? `${context.app_name} — ${context.url}` : context.app_name;

    if (appInfo) {
      parts.push(`[Context: ${appInfo}]`);
    }

    if (context.selected_text) {
      // Truncate very long selections
      const selected =
        context.selected_text.length > 500
          ? context.selected_text.slice(0, 500) + "..."
          : context.selected_text;
      parts.push(`[Selected: "${selected}"]`);
    }
  }

  if (parts.length > 0) {
    parts.push(""); // blank line between context and prompt
  }

  parts.push(transcription);

  return parts.join("\n");
}
