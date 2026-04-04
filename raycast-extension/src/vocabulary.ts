import { environment, AI, showToast, Toast } from "@raycast/api";
import { existsSync, readFileSync, writeFileSync, mkdirSync } from "fs";
import { join } from "path";

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
 * Extract vocabulary corrections by comparing original and edited text.
 *
 * Uses Raycast AI to intelligently identify word substitutions that look
 * like speech-to-text corrections (not semantic rewrites).
 *
 * Falls back to simple word-level diffing if AI is unavailable.
 */
export async function extractCorrections(
  original: string,
  edited: string,
): Promise<Array<{ from: string; to: string }>> {
  // Don't bother if the texts are identical or either is empty
  if (original.trim() === edited.trim()) return [];
  if (!original.trim() || !edited.trim()) return [];

  // Try AI-powered extraction first
  try {
    return await extractCorrectionsWithAI(original, edited);
  } catch {
    // Fall back to simple word diff
    return extractCorrectionsSimple(original, edited);
  }
}

/**
 * AI-powered correction extraction.
 * Asks Raycast AI to compare the texts and return vocabulary corrections as JSON.
 */
async function extractCorrectionsWithAI(
  original: string,
  edited: string,
): Promise<Array<{ from: string; to: string }>> {
  const prompt = `Compare these two texts. The first is speech-to-text output, the second is the user's corrected version.

ORIGINAL: "${original}"
EDITED: "${edited}"

Identify word-level corrections where the user fixed a speech-to-text error (misspellings, wrong words, technical terms the STT got wrong). Do NOT include:
- Intentional rephrasing or added/removed sentences
- Punctuation-only changes
- Capitalization-only changes

Return ONLY a JSON array of corrections. Each item has "from" (original wrong word/phrase) and "to" (corrected word/phrase). If no STT corrections were made, return an empty array.

Example: [{"from": "loggin", "to": "login"}, {"from": "reack", "to": "React"}]

JSON:`;

  const response = await AI.ask(prompt, { creativity: 0 });

  // Parse the JSON from the response
  const jsonMatch = response.match(/\[[\s\S]*\]/);
  if (!jsonMatch) return [];

  const parsed = JSON.parse(jsonMatch[0]) as Array<{ from: string; to: string }>;

  // Validate the structure
  return parsed.filter(
    (item) =>
      typeof item.from === "string" &&
      typeof item.to === "string" &&
      item.from.trim().length > 0 &&
      item.to.trim().length > 0 &&
      item.from !== item.to,
  );
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

  // Simple positional comparison using longest common subsequence approach
  // to align words and find substitutions
  const len = Math.min(origWords.length, editWords.length);
  for (let i = 0; i < len; i++) {
    const origWord = origWords[i];
    const editWord = editWords[i];

    // Skip if identical (case-insensitive for this check)
    if (origWord.toLowerCase() === editWord.toLowerCase()) continue;

    // Skip pure punctuation differences
    const origClean = origWord.replace(/[^\w]/g, "");
    const editClean = editWord.replace(/[^\w]/g, "");
    if (origClean.toLowerCase() === editClean.toLowerCase()) continue;

    // This looks like a word substitution — likely an STT correction
    corrections.push({ from: origWord, to: editWord });
  }

  return corrections;
}

/**
 * Learn from a prompt edit: extract corrections and merge into vocabulary.
 * Called after dispatch when the user has edited the prompt text.
 * Returns the number of new corrections learned.
 */
export async function learnFromEdit(original: string, edited: string): Promise<number> {
  const corrections = await extractCorrections(original, edited);
  if (corrections.length === 0) return 0;

  mergeCorrections(corrections);

  await showToast({
    style: Toast.Style.Success,
    title: `Learned ${corrections.length} word${corrections.length === 1 ? "" : "s"}`,
    message: corrections.map((c) => `${c.from} → ${c.to}`).join(", "),
  });

  return corrections.length;
}
