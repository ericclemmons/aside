import { AppProvider } from "./context/AppContext";
import { OverlayWindow } from "./components/OverlayWindow";

export default function App() {
  return (
    <AppProvider>
      <OverlayWindow />
    </AppProvider>
  );
}
