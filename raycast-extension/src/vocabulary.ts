import { environment, showToast, Toast } from "@raycast/api";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";
import { discoverServer, type DiscoveredServer, dispatch as dispatchToOpenCode } from "./opencode";

/**
 * A vocabulary correction: what the STT engine produced vs what the user meant.
 */
export interface VocabularyEntry {
  /** The misheard/incorrect word(s) */
  from: string;
  /** The corrected word(s) */
  to: string;
  /** How many times this correction has been observed */
  count: number;
  /** When this was last observed */
  lastSeen: string;
}

const VOCAB_FILE = "vocabulary.json";

function vocabPath(): string {
  const dir = environment.supportPath;
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  return join(dir, VOCAB_FILE);
}

/**
 * Load the vocabulary store from disk.
 */
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
 * Save the vocabulary store to disk.
 */
function saveVocabulary(entries: VocabularyEntry[]): void {
  writeFileSync(vocabPath(), JSON.stringify(entries, null, 2));
}

/**
 * Get all learned "correct" words — useful for feeding back to STT engines
 * as custom vocabulary hints.
 */
export function getCustomWords(): string[] {
  const vocab = loadVocabulary();
  return [...new Set(vocab.map((e) => e.to))];
}

/**
 * Merge new corrections into the vocabulary store.
 * Increments count for existing entries, adds new ones.
 */
export function mergeCorrections(corrections: Array<{ from: string; to: string }>): void {
  const vocab = loadVocabulary();
  const now = new Date().toISOString();

  for (const correction of corrections) {
    const fromLower = correction.from.toLowerCase();
    const existing = vocab.find((e) => e.from.toLowerCase() === fromLower && e.to === correction.to);
    if (existing) {
      existing.count += 1;
      existing.lastSeen = now;
    } else {
      vocab.push({
        from: correction.from,
        to: correction.to,
        count: 1,
        lastSeen: now,
      });
    }
  }

  saveVocabulary(vocab);
}

/**
 * Extract vocabulary corrections by dispatching to OpenCode.
 *
 * Sends a prompt to OpenCode asking it to compare the original and edited
 * text, identify STT corrections, and write them directly to the vocabulary
 * file. Falls back to simple word-level diffing if OpenCode is unavailable.
 */
export async function extractCorrections(
  original: string,
  edited: string,
  server?: DiscoveredServer | null,
): Promise<Array<{ from: string; to: string }>> {
  if (original.trim() === edited.trim()) return [];
  if (!original.trim() || !edited.trim()) return [];

  // Try OpenCode-powered extraction first
  const activeServer = server ?? discoverServer();
  if (activeServer) {
    try {
      return await extractCorrectionsViaOpenCode(original, edited, activeServer);
    } catch {
      // Fall back to simple word diff
    }
  }

  return extractCorrectionsSimple(original, edited);
}

/**
 * Dispatch a prompt to OpenCode to compare the two texts and update the
 * vocabulary file. OpenCode writes the file directly — we then read it
 * back to see what was added.
 */
async function extractCorrectionsViaOpenCode(
  original: string,
  edited: string,
  server: DiscoveredServer,
): Promise<Array<{ from: string; to: string }>> {
  const path = vocabPath();
  const currentVocab = loadVocabulary();

  const prompt = `Compare these 2 prompts. The 1st is speech-to-text output, the 2nd is the user's corrected version. If it looks like the user corrected a typo or STT error from the 1st prompt, update ${path} with the new words or phrases.

ORIGINAL: "${original}"
CORRECTED: "${edited}"

The vocabulary file schema is a JSON array of objects:
[{"from": "misheard_word", "to": "correct_word", "count": 1, "lastSeen": "${new Date().toISOString()}"}]

Rules:
- Only add entries for actual STT corrections (wrong word → right word)
- Do NOT add entries for intentional rephrasing, added/removed sentences, or punctuation changes
- If an entry with the same "from" and "to" already exists, increment its "count" and update "lastSeen"
- If no corrections were made, leave the file unchanged
- Write valid JSON to the file

Current file contents:
${JSON.stringify(currentVocab, null, 2)}`;

  const result = await dispatchToOpenCode({
    prompt,
    server,
    timeout: 15000,
  });

  if (!result.success) {
    throw new Error(result.error || "OpenCode dispatch failed");
  }

  // Read back the file to see what OpenCode wrote
  // Give it a moment to finish writing
  await new Promise((resolve) => setTimeout(resolve, 2000));

  const updatedVocab = loadVocabulary();

  // Diff against what we had before to find new corrections
  const newEntries = updatedVocab.filter(
    (updated) => !currentVocab.some((existing) => existing.from === updated.from && existing.to === updated.to),
  );

  return newEntries.map((e) => ({ from: e.from, to: e.to }));
}

/**
 * Simple word-level diff fallback.
 * Compares words at the same position and identifies substitutions.
 */
function extractCorrectionsSimple(
  original: string,
  edited: string,
): Array<{ from: string; to: string }> {
  const corrections: Array<{ from: string; to: string }> = [];

  const origWords = original.split(/\s+/).filter(Boolean);
  const editWords = edited.split(/\s+/).filter(Boolean);

  // Only compare if the texts have roughly the same number of words
  // (suggesting corrections, not a full rewrite)
  if (Math.abs(origWords.length - editWords.length) > origWords.length * 0.3) {
    return [];
  }

  const len = Math.min(origWords.length, editWords.length);
  for (let i = 0; i < len; i++) {
    const origWord = origWords[i];
    const editWord = editWords[i];

    if (origWord.toLowerCase() === editWord.toLowerCase()) continue;

    const origClean = origWord.replace(/[^\w]/g, "");
    const editClean = editWord.replace(/[^\w]/g, "");
    if (origClean.toLowerCase() === editClean.toLowerCase()) continue;

    corrections.push({ from: origWord, to: editWord });
  }

  return corrections;
}

/**
 * Learn from a prompt edit: extract corrections and merge into vocabulary.
 * Called after dispatch when the user has edited the prompt text.
 * Returns the number of new corrections learned.
 */
export async function learnFromEdit(
  original: string,
  edited: string,
  server?: DiscoveredServer | null,
): Promise<number> {
  const corrections = await extractCorrections(original, edited, server);
  if (corrections.length === 0) return 0;

  // If OpenCode already wrote the file, corrections are already persisted.
  // If we used the simple fallback, we need to merge them ourselves.
  // mergeCorrections is idempotent (increments count if already exists),
  // so it's safe to call either way.
  mergeCorrections(corrections);

  await showToast({
    style: Toast.Style.Success,
    title: `Learned ${corrections.length} word${corrections.length === 1 ? "" : "s"}`,
    message: corrections.map((c) => `${c.from} → ${c.to}`).join(", "),
  });

  return corrections.length;
}
