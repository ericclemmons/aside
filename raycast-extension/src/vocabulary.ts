import { showToast, Toast } from "@raycast/api";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { dispatch, type DiscoveredServer } from "./opencode";

/**
 * Path to the shared custom_words.json used by the native Aside app's STT engines.
 * Whisper uses these as initialPrompt, Apple STT uses them as contextualStrings.
 * OpenCode writes to this file directly — the words are immediately available
 * to the next transcription.
 */
const CUSTOM_WORDS_DIR = join(
  process.env.HOME ?? "",
  "Library/Application Support/com.erriclemmons.aside.app",
);
const CUSTOM_WORDS_PATH = join(CUSTOM_WORDS_DIR, "custom_words.json");

export function customWordsPath(): string {
  return CUSTOM_WORDS_PATH;
}

export function loadCustomWords(): string[] {
  if (!existsSync(CUSTOM_WORDS_PATH)) return [];
  try {
    return JSON.parse(readFileSync(CUSTOM_WORDS_PATH, "utf-8")) as string[];
  } catch {
    return [];
  }
}

/**
 * After a successful dispatch, if the user edited the prompt, ask OpenCode
 * to compare before/after and add corrected words to custom_words.json.
 * These words are immediately picked up by the STT engine on next recording.
 */
export async function learnFromEdit(
  original: string,
  edited: string,
  server: DiscoveredServer,
): Promise<void> {
  if (original.trim() === edited.trim()) return;

  // Ensure the file exists so OpenCode can read/write it
  if (!existsSync(CUSTOM_WORDS_DIR)) mkdirSync(CUSTOM_WORDS_DIR, { recursive: true });
  if (!existsSync(CUSTOM_WORDS_PATH)) writeFileSync(CUSTOM_WORDS_PATH, "[]");

  const currentWords = loadCustomWords();

  const prompt = `Compare these 2 prompts. The 1st is speech-to-text output, the 2nd is the user's corrected version. If it looks like the user corrected a typo or STT error from the 1st prompt, update ${CUSTOM_WORDS_PATH} with the new words or phrases.

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
