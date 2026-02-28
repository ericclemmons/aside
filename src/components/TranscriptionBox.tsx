import { useEffect, useRef } from "react";

interface TranscriptionBoxProps {
  text: string;
  onChange: (text: string) => void;
  isProcessing: boolean;
}

export function TranscriptionBox({ text, onChange, isProcessing }: TranscriptionBoxProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Place cursor at end when text first appears
  useEffect(() => {
    if (text && textareaRef.current) {
      const el = textareaRef.current;
      el.focus();
      el.setSelectionRange(el.value.length, el.value.length);
    }
  }, [text]);

  if (isProcessing) {
    return (
      <div className="flex items-center justify-center py-4">
        <div className="flex gap-1">
          <span className="w-1.5 h-1.5 bg-white/40 rounded-full animate-bounce [animation-delay:0ms]" />
          <span className="w-1.5 h-1.5 bg-white/40 rounded-full animate-bounce [animation-delay:150ms]" />
          <span className="w-1.5 h-1.5 bg-white/40 rounded-full animate-bounce [animation-delay:300ms]" />
        </div>
      </div>
    );
  }

  if (!text) return null;

  return (
    <textarea
      ref={textareaRef}
      value={text}
      onChange={(e) => onChange(e.target.value)}
      className="w-full bg-white/5 border border-white/10 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 resize-none focus:outline-none focus:border-purple-500/50 transition-colors"
      rows={3}
      placeholder="Transcribed text will appear here..."
      autoFocus
    />
  );
}
