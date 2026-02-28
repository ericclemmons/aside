import { useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { AppProvider } from "./context/AppContext";
import { OverlayWindow } from "./components/OverlayWindow";

function ModelLoader() {
  useEffect(() => {
    // Attempt to load the Parakeet model on startup
    invoke("load_model", { modelDir: "./models" }).catch((e) => {
      console.warn(
        "Failed to load model on startup (expected if models not downloaded yet):",
        e
      );
    });
  }, []);

  return null;
}

export default function App() {
  return (
    <AppProvider>
      <ModelLoader />
      <OverlayWindow />
    </AppProvider>
  );
}
