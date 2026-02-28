export type AppPhase =
  | "idle"
  | "recording"
  | "processing"
  | "ready";

export type CliProvider = "claude" | "opencode";

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

export interface AppState {
  phase: AppPhase;
  transcription: string;
  activeContext: ActiveContext | null;
  /** Which provider tab is active */
  activeProvider: CliProvider;
  /** Sessions keyed by provider */
  sessions: Record<CliProvider, Session[]>;
  /** Selected session index within active provider (-1 = "New Session") */
  selectedSessionIndex: number;
  /** Audio amplitude levels for waveform visualization */
  audioLevels: number[];
  /** Error message if something went wrong */
  error: string | null;
}

export type AppAction =
  | { type: "START_RECORDING" }
  | { type: "STOP_RECORDING" }
  | { type: "TRANSCRIPTION_COMPLETE"; text: string }
  | { type: "SET_TRANSCRIPTION"; text: string }
  | { type: "SET_CONTEXT"; context: ActiveContext }
  | { type: "SET_SESSIONS"; provider: CliProvider; sessions: Session[] }
  | { type: "SET_PROVIDER"; provider: CliProvider }
  | { type: "SET_SESSION_INDEX"; index: number }
  | { type: "PUSH_AUDIO_LEVEL"; level: number }
  | { type: "DISPATCH" }
  | { type: "CANCEL" }
  | { type: "SET_ERROR"; error: string }
  | { type: "CLEAR_ERROR" };

export const initialState: AppState = {
  phase: "idle",
  transcription: "",
  activeContext: null,
  activeProvider: "claude",
  sessions: { claude: [], opencode: [] },
  selectedSessionIndex: -1,
  audioLevels: [],
  error: null,
};
