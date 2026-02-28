import { useRef, useEffect } from "react";

interface WaveformProps {
  levels: number[];
  isActive: boolean;
}

// Max amplitude: baseAmp = 3 + 14*1.0 = 17, combined sines peak ~1.7x → ~29px deflection
// Need 2x for above+below center, plus margin → 64px
const WAVE_HEIGHT = 64;
const NUM_POINTS = 64;

const WAVE_COLORS = [
  { start: "rgba(0, 0, 0, 0.4)", end: "rgba(0, 0, 0, 0.1)" },
  { start: "rgba(255, 255, 255, 0.5)", end: "rgba(255, 255, 255, 0.12)" },
  { start: "rgba(255, 255, 255, 0.9)", end: "rgba(255, 255, 255, 0.2)" },
];

/**
 * Siri-inspired fluid waveform visualizer.
 * Layered sine waves with vibrant gradient strokes, responsive to audio.
 */
export function Waveform({ levels, isActive }: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);
  const timeRef = useRef(0);
  const smoothLevelRef = useRef(0);
  const levelsRef = useRef(levels);
  const activeRef = useRef(isActive);
  levelsRef.current = levels;
  activeRef.current = isActive;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    function draw() {
      if (!canvas || !ctx) return;

      const active = activeRef.current;
      const lvls = levelsRef.current;

      const dpr = window.devicePixelRatio || 1;
      const w = canvas.clientWidth;
      const h = canvas.clientHeight;

      if (canvas.width !== w * dpr || canvas.height !== h * dpr) {
        canvas.width = w * dpr;
        canvas.height = h * dpr;
        ctx.scale(dpr, dpr);
      }

      // Mic RMS is typically 0.001–0.1; boost aggressively so waveform is clearly visible
      const rawLevel = active && lvls.length > 0 ? Math.min(lvls[lvls.length - 1] * 80, 1.0) : 0;
      const lerp = active ? 0.4 : 0.08;
      smoothLevelRef.current += (rawLevel - smoothLevelRef.current) * lerp;
      // Floor at 0.15 while recording so the wave always shows movement
      const level = active ? Math.max(smoothLevelRef.current, 0.15) : smoothLevelRef.current;

      const speed = active ? 0.03 : 0.012;
      timeRef.current += speed;
      const t = timeRef.current;

      ctx.clearRect(0, 0, w, h);

      const centerY = h / 2;

      const waves = [
        { freq: 2.5, phase: 0, ampScale: 0.6 },
        { freq: 3.2, phase: 1.8, ampScale: 0.85 },
        { freq: 2.0, phase: 3.5, ampScale: 1.0 },
      ];

      for (let wi = 0; wi < waves.length; wi++) {
        const wave = waves[wi];
        const colors = WAVE_COLORS[wi];

        // Scale amplitude to canvas height so waves never clip
        // Max combined sine factor: 1 + 0.4 + 0.3 = 1.7
        const maxDeflection = (h / 2) * 0.85; // leave 15% margin
        const maxAmp = maxDeflection / 1.7;
        const baseAmp = active
          ? (3 + Math.min(level * 90, maxAmp - 3)) * wave.ampScale
          : 2 * wave.ampScale;

        ctx.beginPath();

        const points: { x: number; y: number }[] = [];
        for (let i = 0; i <= NUM_POINTS; i++) {
          const x = (i / NUM_POINTS) * w;
          const nx = i / NUM_POINTS;

          const s1 = Math.sin(nx * Math.PI * wave.freq + t * 3 + wave.phase);
          const s2 = Math.sin(nx * Math.PI * (wave.freq * 1.7) + t * 2.3 + wave.phase * 0.7) * 0.4;
          const s3 = Math.sin(nx * Math.PI * (wave.freq * 0.5) + t * 1.1 + wave.phase * 1.3) * 0.3;

          const edge = Math.sin(nx * Math.PI);
          const y = centerY + (s1 + s2 + s3) * baseAmp * edge;

          points.push({ x, y });
        }

        // Catmull-Rom → bezier
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 0; i < points.length - 1; i++) {
          const p0 = points[Math.max(0, i - 1)];
          const p1 = points[i];
          const p2 = points[i + 1];
          const p3 = points[Math.min(points.length - 1, i + 2)];

          ctx.bezierCurveTo(
            p1.x + (p2.x - p0.x) / 6,
            p1.y + (p2.y - p0.y) / 6,
            p2.x - (p3.x - p1.x) / 6,
            p2.y - (p3.y - p1.y) / 6,
            p2.x,
            p2.y,
          );
        }

        // Gradient stroke along the wave
        const grad = ctx.createLinearGradient(0, 0, w, 0);
        const dimFactor = active ? 1.0 : 0.3;
        grad.addColorStop(0, applyDim(colors.end, dimFactor));
        grad.addColorStop(0.3, applyDim(colors.start, dimFactor));
        grad.addColorStop(0.7, applyDim(colors.start, dimFactor));
        grad.addColorStop(1, applyDim(colors.end, dimFactor));

        ctx.strokeStyle = grad;
        ctx.lineWidth = active ? 2 : 1.2;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        ctx.stroke();
      }

      animRef.current = requestAnimationFrame(draw);
    }

    animRef.current = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(animRef.current);
  }, []);

  return (
    <canvas
      ref={canvasRef}
      className="w-[calc(100%+2rem)] -mx-4 overflow-visible"
      style={{ height: WAVE_HEIGHT }}
    />
  );
}

/** Dim an rgba color by multiplying its alpha */
function applyDim(rgba: string, factor: number): string {
  const m = rgba.match(/rgba?\((\d+),\s*(\d+),\s*(\d+),?\s*([\d.]+)?\)/);
  if (!m) return rgba;
  const a = (parseFloat(m[4] ?? "1") * factor).toFixed(2);
  return `rgba(${m[1]}, ${m[2]}, ${m[3]}, ${a})`;
}
