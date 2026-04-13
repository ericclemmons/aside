import { environment, showToast, Toast } from "@raycast/api";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { dispatch, type DiscoveredServer } from "./opencode";

const CUSTOM_WORDS_FILE = "custom_words.json";

export function customWordsPath(): string {
  const dir = environment.supportPath;
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return join(dir, CUSTOM_WORDS_FILE);
}

export function loadCustomWords(): string[] {
  const path = customWordsPath();
  if (!existsSync(path)) return [];
  try {
    return JSON.parse(readFileSync(path, "utf-8")) as string[];
  } catch {
    return [];
  }
}

/**
 * After a successful dispatch, if the user edited the prompt, ask OpenCode
 * to compare before/after and add corrected words to custom_words.json.
 */
export async function learnFromEdit(
  original: string,
  edited: string,
  server: DiscoveredServer,
): Promise<void> {
  if (original.trim() === edited.trim()) return;

  const path = customWordsPath();
  if (!existsSync(path)) writeFileSync(path, "[]");

  const currentWords = loadCustomWords();

  const prompt = `Compare these 2 prompts. The 1st is speech-to-text output, the 2nd is the user's corrected version. If it looks like the user corrected a typo or STT error from the 1st prompt, update ${path} with the new words or phrases.

ORIGINAL: "${original}"
CORRECTED: "${edited}"

The file is a JSON array of strings — words/phrases the speech-to-text engine should recognize:
${JSON.stringify(currentWords)}

Rules:
- Add the CORRECTED version of any word the user fixed (not the misspelling)
- Don't add common English words — only names, technical terms, abbreviations
- Don't duplicate words already in the array
- If no corrections found, leave the file unchanged`;

  const result = await dispatch({ prompt, server, timeout: 30000 });
  if (!result.success) return;

  const updatedWords = loadCustomWords();
  const newWords = updatedWords.filter((w) => !currentWords.includes(w));

  if (newWords.length > 0) {
    await showToast({
      style: Toast.Style.Success,
      title: `Learned: ${newWords.join(", ")}`,
    });
  }
}
