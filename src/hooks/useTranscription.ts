import { useAppState } from "../context/AppContext";

/**
 * Provides the current transcription text and a setter for editing.
 * The transcription is populated by useHotkey after recording stops.
 */
export function useTranscription() {
  const { state, dispatch } = useAppState();

  function setTranscription(text: string) {
    dispatch({ type: "SET_TRANSCRIPTION", text });
  }

  return {
    transcription: state.transcription,
    setTranscription,
    isProcessing: state.phase === "processing",
  };
}
