export type AppPhase = "setup" | "idle" | "recording" | "processing" | "ready";

export interface ActiveContext {
  app_name: string;
  window_title: string;
  url: string | null;
  selected_text: string | null;
}

export interface Session {
  id: string;
  name: string;
  lastActive: string;
}

export type SttBackend = "apple" | "parakeet";

export interface AppState {
  phase: AppPhase;
  transcription: string;
  activeContext: ActiveContext | null;
  /** Recent opencode sessions, sorted by last updated */
  sessions: Session[];
  /** Selected session index (-1 = "New Session") */
  selectedSessionIndex: number;
  /** Audio amplitude levels for waveform visualization */
  audioLevels: number[];
  /** Error message if something went wrong */
  error: string | null;
  /** Active STT backend */
  sttBackend: SttBackend;
}

export type AppAction =
  | { type: "START_RECORDING" }
  | { type: "STOP_RECORDING" }
  | { type: "TRANSCRIPTION_COMPLETE"; text: string }
  | { type: "SET_TRANSCRIPTION"; text: string }
  | { type: "SET_CONTEXT"; context: ActiveContext }
  | { type: "SET_SESSIONS"; sessions: Session[] }
  | { type: "SET_SESSION_INDEX"; index: number }
  | { type: "PUSH_AUDIO_LEVEL"; level: number }
  | { type: "DISPATCH" }
  | { type: "CANCEL" }
  | { type: "SET_ERROR"; error: string }
  | { type: "CLEAR_ERROR" }
  | { type: "SET_STT_BACKEND"; backend: SttBackend }
  | { type: "SETUP_COMPLETE" };

export const initialState: AppState = {
  phase: "setup",
  transcription: "",
  activeContext: null,
  sessions: [],
  selectedSessionIndex: -1,
  audioLevels: [],
  error: null,
  sttBackend: "parakeet",
};
