import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { Command } from "@tauri-apps/plugin-shell";
// Mic permission via our own Rust commands (AVCaptureDevice)
import { useAppState } from "../context/AppContext";
import { Waveform } from "./Waveform";

type Step =
  | "checking"
  | "need_microphone"
  | "waiting_microphone"
  | "need_accessibility"
  | "waiting_accessibility"
  | "need_automation"
  | "waiting_automation"
  | "need_model"
  | "downloading_model"
  | "loading_model"
  | "ready"
  | "error";

const PARAKEET_BASE_URL =
  "https://huggingface.co/onnx-community/parakeet-ctc-0.6b-ONNX/resolve/main";
const PARAKEET_FILES = [
  { path: "onnx/model_quantized.onnx", name: "model_quantized.onnx", size: "1.4 MB" },
  { path: "onnx/model_quantized.onnx_data", name: "model_quantized.onnx_data", size: "611 MB" },
  { path: "tokenizer.json", name: "tokenizer.json", size: "412 KB" },
  { path: "config.json", name: "config.json", size: "1 KB" },
  { path: "preprocessor_config.json", name: "preprocessor_config.json", size: "314 B" },
];

/**
 * Setup screen shown on first launch.
 * 1. Accessibility permission (for CGEvent tap hotkey)
 * 2. Automation permission (for System Events / active app detection)
 * 3. Parakeet model download + load
 *
 * Note: OpenCode server is started by Rust before this screen loads.
 * If `opencode` is not in PATH, the app will show a fatal dialog and exit.
 */
export function SetupScreen() {
  const { dispatch } = useAppState();
  const [step, setStep] = useState<Step>("checking");
  const [error, setError] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState("");
  const [modelDir, setModelDir] = useState<string | null>(null);
  const pollRef = useRef<ReturnType<typeof setInterval>>();

  const [fakeLevels, setFakeLevels] = useState<number[]>([]);
  useEffect(() => {
    const id = setInterval(() => {
      setFakeLevels((prev) => {
        const next = [...prev, 0.15 + Math.random() * 0.35];
        return next.length > 60 ? next.slice(-60) : next;
      });
    }, 33);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    invoke("show_overlay", { alwaysOnTop: false });
  }, []);

  useEffect(() => {
    runChecks();
  }, []);

  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  async function runChecks() {
    setStep("checking");
    setError(null);

    try {
      // Resolve absolute model path from Rust (avoids CWD mismatches)
      const dir = await invoke<string>("get_model_dir", { name: "parakeet" });
      setModelDir(dir);

      // 1. Microphone permission (must be first — cpal silently gets zeros without it)
      const micStatus = await invoke<string>("check_microphone");
      const hasMic = micStatus === "authorized";
      if (!hasMic) {
        setStep("need_microphone");
        return;
      }

      // 2. Accessibility (for CGEvent tap hotkey)
      const hasAccessibility = await invoke<boolean>("check_accessibility");
      if (!hasAccessibility) {
        setStep("need_accessibility");
        return;
      }
      await checkAutomationAndContinue(dir);
    } catch (e) {
      setError(String(e));
      setStep("error");
    }
  }

  async function checkAutomationAndContinue(dir?: string) {
    const d = dir ?? modelDir!;
    const hasAutomation = await invoke<boolean>("check_automation");
    if (!hasAutomation) {
      setStep("need_automation");
      return;
    }
    await checkAndLoadModel(d);
  }

  async function checkAndLoadModel(dir?: string) {
    const d = dir ?? modelDir!;
    const hasModel = await invoke<boolean>("check_parakeet_model_exists", {
      modelDir: d,
    });

    if (hasModel) {
      await loadModel(d);
    } else {
      // Auto-download without requiring a click
      setStep("downloading_model");
      await handleDownloadModel(d);
    }
  }

  async function loadModel(dir?: string) {
    const d = dir ?? modelDir!;
    setStep("loading_model");
    try {
      await invoke("load_parakeet_model", { modelDir: d });
      await finishSetup();
    } catch (e) {
      setError(`Failed to load model: ${e}`);
      setStep("error");
    }
  }

  async function handleDownloadModel(dir?: string) {
    setStep("downloading_model");
    setDownloadProgress("Preparing download...");
    setError(null);

    try {
      const d = dir ?? modelDir!;
      for (let i = 0; i < PARAKEET_FILES.length; i++) {
        const file = PARAKEET_FILES[i];
        setDownloadProgress(`${file.name} (${file.size}) [${i + 1}/${PARAKEET_FILES.length}]`);

        const destPath = `${d}/${file.name}`;
        const url = `${PARAKEET_BASE_URL}/${file.path}`;

        const cmd = Command.create("sh", [
          "-c",
          `mkdir -p "${d}" && curl -fSL --progress-bar "${url}" -o "${destPath}" 2>&1`,
        ]);

        cmd.stderr.on("data", (data) => {
          const line = data.trim();
          if (line) {
            setDownloadProgress(`${file.name} [${i + 1}/${PARAKEET_FILES.length}]: ${line}`);
          }
        });

        const result = await cmd.execute();
        if (result.code !== 0) {
          throw new Error(`Failed to download ${file.name}: ${result.stderr}`);
        }
      }

      setDownloadProgress("Download complete!");
      await loadModel(d);
    } catch (e) {
      setError(String(e));
      setStep("error");
    }
  }

  async function handleGrantMicrophone() {
    // Request via AVCaptureDevice — triggers the macOS system dialog
    await invoke("request_microphone");

    setStep("waiting_microphone");

    pollRef.current = setInterval(async () => {
      const micStatus = await invoke<string>("check_microphone");
      const granted = micStatus === "authorized";
      if (granted) {
        if (pollRef.current) clearInterval(pollRef.current);
        try {
          const hasAccessibility = await invoke<boolean>("check_accessibility");
          if (!hasAccessibility) {
            setStep("need_accessibility");
            return;
          }
          await checkAutomationAndContinue(modelDir ?? undefined);
        } catch (e) {
          setError(String(e));
          setStep("error");
        }
      }
    }, 1000);
  }

  async function handleGrantAccessibility() {
    await invoke<boolean>("request_accessibility");
    setStep("waiting_accessibility");

    pollRef.current = setInterval(async () => {
      const granted = await invoke<boolean>("check_accessibility");
      if (granted) {
        if (pollRef.current) clearInterval(pollRef.current);
        try {
          await checkAutomationAndContinue(modelDir ?? undefined);
        } catch (e) {
          setError(String(e));
          setStep("error");
        }
      }
    }, 1000);
  }

  async function handleGrantAutomation() {
    // This triggers the macOS "wants to control System Events" dialog
    await invoke<boolean>("request_automation");
    setStep("waiting_automation");

    pollRef.current = setInterval(async () => {
      const granted = await invoke<boolean>("check_automation");
      if (granted) {
        if (pollRef.current) clearInterval(pollRef.current);
        try {
          await checkAndLoadModel(modelDir ?? undefined);
        } catch (e) {
          setError(String(e));
          setStep("error");
        }
      }
    }, 1000);
  }

  async function finishSetup() {
    setStep("ready");
    await invoke("start_hotkey_listener");
    setTimeout(() => {
      dispatch({ type: "SETUP_COMPLETE" });
      invoke("hide_overlay");
    }, 1500);
  }

  function renderStepContent() {
    switch (step) {
      case "checking":
        return (
          <div className="flex items-center gap-2 py-2">
            <Spinner />
            <span className="text-xs text-white/60">Checking dependencies...</span>
          </div>
        );

      case "need_microphone":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="needed" />
            <p className="text-xs text-white/50 text-center">
              Aside needs microphone access to record your voice for transcription
            </p>
            <button
              onClick={handleGrantMicrophone}
              className="w-full px-3 py-2 text-xs font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-lg transition-colors"
            >
              Grant Microphone Access
            </button>
          </div>
        );

      case "waiting_microphone":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="waiting" />
            <p className="text-[10px] text-white/30 text-center">
              Enable Aside in System Settings &gt; Privacy &gt; Microphone, then it will continue
              automatically
            </p>
          </div>
        );

      case "need_accessibility":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="needed" />
            <p className="text-xs text-white/50 text-center">
              Aside needs keyboard access to detect the{" "}
              <kbd className="px-1 py-0.5 bg-white/10 rounded text-[10px] text-white/70">
                Right Option
              </kbd>{" "}
              key
            </p>
            <button
              onClick={handleGrantAccessibility}
              className="w-full px-3 py-2 text-xs font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-lg transition-colors"
            >
              Grant Keyboard Access
            </button>
          </div>
        );

      case "waiting_accessibility":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="waiting" />
            <p className="text-[10px] text-white/30 text-center">
              Toggle Aside in System Settings &gt; Privacy &gt; Accessibility, then it will continue
              automatically
            </p>
          </div>
        );

      case "need_automation":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="done" />
            <CheckItem label="System Events Access" status="needed" />
            <p className="text-xs text-white/50 text-center">
              Aside needs Automation access to detect active apps and windows
            </p>
            <button
              onClick={handleGrantAutomation}
              className="w-full px-3 py-2 text-xs font-medium text-white bg-purple-600 hover:bg-purple-500 rounded-lg transition-colors"
            >
              Grant Automation Access
            </button>
          </div>
        );

      case "waiting_automation":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="done" />
            <CheckItem label="System Events Access" status="waiting" />
            <p className="text-[10px] text-white/30 text-center">
              Click Allow in the macOS dialog, then it will continue automatically
            </p>
          </div>
        );

      case "need_model":
      case "downloading_model":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="done" />
            <CheckItem label="System Events Access" status="done" />

            <CheckItem label="Parakeet Model" status="downloading" />
            <div className="text-[10px] text-white/40 text-center font-mono truncate px-2">
              {downloadProgress}
            </div>
          </div>
        );

      case "loading_model":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="done" />
            <CheckItem label="System Events Access" status="done" />

            <CheckItem label="Parakeet Model" status="loading" />
          </div>
        );

      case "ready":
        return (
          <div className="flex flex-col gap-2">
            <CheckItem label="Microphone Access" status="done" />
            <CheckItem label="Keyboard Access" status="done" />
            <CheckItem label="System Events Access" status="done" />

            <CheckItem label="Parakeet Model" status="done" />
            <div className="flex items-center justify-center gap-2 py-1">
              <span className="relative flex h-2 w-2">
                <span className="absolute inline-flex h-full w-full rounded-full bg-green-500 opacity-75 animate-ping" />
                <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500" />
              </span>
              <span className="text-xs text-green-400">Ready — press Right Option to start</span>
            </div>
          </div>
        );

      case "error":
        return (
          <div className="flex flex-col gap-2">
            <div className="text-xs text-red-400 bg-red-500/10 rounded px-2 py-1.5">{error}</div>
            <button
              onClick={runChecks}
              className="w-full px-3 py-2 text-xs font-medium text-white bg-white/10 hover:bg-white/15 rounded-lg transition-colors"
            >
              Retry
            </button>
          </div>
        );
    }
  }

  return (
    <div className="w-full h-full flex flex-col gap-3 p-4" data-tauri-drag-region>
      <div className="flex items-center gap-2">
        <span className="text-sm font-medium text-white/90">Aside</span>
        <span className="text-[10px] text-white/30">Setup</span>
      </div>

      <Waveform levels={fakeLevels} isActive={true} />

      {renderStepContent()}
    </div>
  );
}

function Spinner() {
  return (
    <svg className="animate-spin h-3 w-3 text-white/60" viewBox="0 0 24 24" fill="none">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path
        className="opacity-75"
        fill="currentColor"
        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
      />
    </svg>
  );
}

function CheckItem({
  label,
  status,
}: {
  label: string;
  status: "done" | "needed" | "waiting" | "downloading" | "loading";
}) {
  return (
    <div className="flex items-center gap-2 text-xs">
      {status === "done" ? (
        <span className="text-green-400">&#10003;</span>
      ) : status === "waiting" || status === "downloading" || status === "loading" ? (
        <Spinner />
      ) : (
        <span className="text-white/30">&#9675;</span>
      )}
      <span className={status === "done" ? "text-white/60" : "text-white/80"}>{label}</span>
      {status === "waiting" && (
        <span className="text-[10px] text-yellow-400/60 ml-auto">Waiting...</span>
      )}
      {status === "downloading" && (
        <span className="text-[10px] text-blue-400/60 ml-auto">Downloading...</span>
      )}
      {status === "loading" && (
        <span className="text-[10px] text-blue-400/60 ml-auto">Loading...</span>
      )}
    </div>
  );
}
