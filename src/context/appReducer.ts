import type { AppState, AppAction } from "./types";

const MAX_AUDIO_LEVELS = 60; // ~2 seconds at 30fps

export function appReducer(state: AppState, action: AppAction): AppState {
  switch (action.type) {
    case "START_RECORDING":
      return {
        ...state,
        phase: "recording",
        transcription: "",
        audioLevels: [],
        error: null,
        selectedSessionIndex: -1,
      };

    case "STOP_RECORDING":
      return {
        ...state,
        phase: "processing",
      };

    case "TRANSCRIPTION_COMPLETE":
      return {
        ...state,
        phase: "ready",
        transcription: action.text,
      };

    case "SET_TRANSCRIPTION":
      return {
        ...state,
        transcription: action.text,
      };

    case "SET_CONTEXT":
      return {
        ...state,
        activeContext: action.context,
      };

    case "SET_SESSIONS":
      return {
        ...state,
        sessions: action.sessions,
      };

    case "SET_SESSION_INDEX":
      return {
        ...state,
        selectedSessionIndex: action.index,
      };

    case "PUSH_AUDIO_LEVEL": {
      const levels = [...state.audioLevels, action.level];
      if (levels.length > MAX_AUDIO_LEVELS) {
        levels.shift();
      }
      return {
        ...state,
        audioLevels: levels,
      };
    }

    case "DISPATCH":
      return {
        ...state,
        phase: "idle",
        transcription: "",
        activeContext: null,
        audioLevels: [],
      };

    case "CANCEL":
      return {
        ...state,
        phase: "idle",
        transcription: "",
        activeContext: null,
        audioLevels: [],
      };

    case "SET_ERROR":
      return {
        ...state,
        error: action.error,
      };

    case "CLEAR_ERROR":
      return {
        ...state,
        error: null,
      };

    case "SET_STT_BACKEND":
      return {
        ...state,
        sttBackend: action.backend,
      };

    case "SETUP_COMPLETE":
      return {
        ...state,
        phase: "idle",
      };

    default:
      return state;
  }
}
