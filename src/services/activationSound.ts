/**
 * Activation sounds using Web Audio API.
 * Pitch-up "ba-doop" on start, pitch-down "do-baap" on stop.
 */

let audioCtx: AudioContext | null = null;

function getAudioContext(): AudioContext {
  if (!audioCtx) {
    audioCtx = new AudioContext();
  }
  return audioCtx;
}

/** Ascending "ba-doop" — played when recording starts */
export function playStartSound() {
  // Two quick ascending tones
  const ctx = getAudioContext();
  const now = ctx.currentTime;

  // First tone: "ba"
  const osc1 = ctx.createOscillator();
  const gain1 = ctx.createGain();
  osc1.type = "sine";
  osc1.frequency.setValueAtTime(440, now);
  gain1.gain.setValueAtTime(0.12, now);
  gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.08);
  osc1.connect(gain1);
  gain1.connect(ctx.destination);
  osc1.start(now);
  osc1.stop(now + 0.08);

  // Second tone: "doop" (higher)
  const osc2 = ctx.createOscillator();
  const gain2 = ctx.createGain();
  osc2.type = "sine";
  osc2.frequency.setValueAtTime(587, now + 0.07);
  gain2.gain.setValueAtTime(0.001, now);
  gain2.gain.setValueAtTime(0.15, now + 0.07);
  gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.2);
  osc2.connect(gain2);
  gain2.connect(ctx.destination);
  osc2.start(now + 0.07);
  osc2.stop(now + 0.2);
}

/** Descending "do-baap" — played when recording stops */
export function playStopSound() {
  const ctx = getAudioContext();
  const now = ctx.currentTime;

  // First tone: "do" (higher)
  const osc1 = ctx.createOscillator();
  const gain1 = ctx.createGain();
  osc1.type = "sine";
  osc1.frequency.setValueAtTime(587, now);
  gain1.gain.setValueAtTime(0.12, now);
  gain1.gain.exponentialRampToValueAtTime(0.001, now + 0.08);
  osc1.connect(gain1);
  gain1.connect(ctx.destination);
  osc1.start(now);
  osc1.stop(now + 0.08);

  // Second tone: "baap" (lower)
  const osc2 = ctx.createOscillator();
  const gain2 = ctx.createGain();
  osc2.type = "sine";
  osc2.frequency.setValueAtTime(440, now + 0.07);
  gain2.gain.setValueAtTime(0.001, now);
  gain2.gain.setValueAtTime(0.15, now + 0.07);
  gain2.gain.exponentialRampToValueAtTime(0.001, now + 0.22);
  osc2.connect(gain2);
  gain2.connect(ctx.destination);
  osc2.start(now + 0.07);
  osc2.stop(now + 0.22);
}
