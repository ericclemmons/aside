import { environment, showToast, Toast } from "@raycast/api";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { dispatch, type DiscoveredServer } from "./opencode";

export interface VocabularyEntry {
  from: string;
  to: string;
  count: number;
  lastSeen: string;
}

const VOCAB_FILE = "vocabulary.json";

export function vocabPath(): string {
  const dir = environment.supportPath;
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return join(dir, VOCAB_FILE);
}

export function loadVocabulary(): VocabularyEntry[] {
  const path = vocabPath();
  if (!existsSync(path)) return [];
  try {
    return JSON.parse(readFileSync(path, "utf-8")) as VocabularyEntry[];
  } catch {
    return [];
  }
}

/**
 * After a successful dispatch, if the user edited the prompt, ask OpenCode
 * to compare before/after and update the vocabulary file directly.
 */
export async function learnFromEdit(
  original: string,
  edited: string,
  server: DiscoveredServer,
): Promise<void> {
  if (original.trim() === edited.trim()) return;

  const path = vocabPath();
  const current = loadVocabulary();

  // Ensure the file exists so OpenCode can read/write it
  if (!existsSync(path)) writeFileSync(path, "[]");

  const prompt = `Compare these 2 prompts. The 1st is speech-to-text output, the 2nd is the user's corrected version. If it looks like the user corrected a typo or STT error from the 1st prompt, update ${path} with the new words or phrases.

ORIGINAL: "${original}"
CORRECTED: "${edited}"

The vocabulary file schema is a JSON array:
[{"from": "misheard_word", "to": "correct_word", "count": 1, "lastSeen": "${new Date().toISOString()}"}]

Rules:
- Only add entries for actual STT corrections (wrong word -> right word)
- Do NOT add entries for rephrasing, added/removed sentences, or punctuation changes
- If a from/to pair already exists, increment its count and update lastSeen
- If no corrections found, leave the file unchanged`;

  const result = await dispatch({ prompt, server, timeout: 30000 });
  if (!result.success) return;

  // Read back what OpenCode wrote to show the user
  const updated = loadVocabulary();
  const newEntries = updated.filter(
    (u) => !current.some((c) => c.from === u.from && c.to === u.to),
  );

  if (newEntries.length > 0) {
    await showToast({
      style: Toast.Style.Success,
      title: `Learned ${newEntries.length} word${newEntries.length === 1 ? "" : "s"}`,
      message: newEntries.map((e) => `${e.from} -> ${e.to}`).join(", "),
    });
  }
}
