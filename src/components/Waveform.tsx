import { useRef, useEffect } from "react";

interface WaveformProps {
  levels: number[];
  isActive: boolean;
}

const BAR_WIDTH = 3;
const BAR_GAP = 2;
const BAR_COLOR = "rgba(139, 92, 246, 0.9)"; // purple-500
const BAR_COLOR_DIM = "rgba(139, 92, 246, 0.3)";

/**
 * Draws animated audio amplitude bars on a canvas.
 * Receives amplitude levels at ~30fps from the audio stream.
 */
export function Waveform({ levels, isActive }: WaveformProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animRef = useRef<number>(0);
  const smoothLevels = useRef<number[]>([]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    function draw() {
      if (!canvas || !ctx) return;

      const { width, height } = canvas;
      const centerY = height / 2;
      const barCount = Math.floor(width / (BAR_WIDTH + BAR_GAP));

      // Smooth levels with decay
      while (smoothLevels.current.length < barCount) {
        smoothLevels.current.push(0);
      }

      // Shift in new levels from the right
      if (levels.length > 0 && isActive) {
        const latest = levels[levels.length - 1];
        smoothLevels.current.push(latest);
        if (smoothLevels.current.length > barCount) {
          smoothLevels.current = smoothLevels.current.slice(-barCount);
        }
      }

      // Apply decay when not active
      if (!isActive) {
        smoothLevels.current = smoothLevels.current.map((l) => l * 0.95);
      }

      ctx.clearRect(0, 0, width, height);

      for (let i = 0; i < barCount; i++) {
        const level = smoothLevels.current[i] || 0;
        // Scale amplitude to bar height (amplitude is typically 0-0.5 for normal speech)
        const barHeight = Math.max(2, level * height * 4);
        const x = i * (BAR_WIDTH + BAR_GAP);

        ctx.fillStyle = isActive ? BAR_COLOR : BAR_COLOR_DIM;
        ctx.beginPath();
        ctx.roundRect(
          x,
          centerY - barHeight / 2,
          BAR_WIDTH,
          barHeight,
          BAR_WIDTH / 2
        );
        ctx.fill();
      }

      animRef.current = requestAnimationFrame(draw);
    }

    draw();

    return () => {
      cancelAnimationFrame(animRef.current);
    };
  }, [levels, isActive]);

  return (
    <canvas
      ref={canvasRef}
      width={380}
      height={80}
      className="w-full h-20"
    />
  );
}
