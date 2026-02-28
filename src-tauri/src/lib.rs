mod audio;
mod context;
mod transcribe;

use parking_lot::Mutex;
use std::sync::Arc;
use tauri::{
    tray::TrayIconBuilder, AppHandle, Emitter, Manager, RunEvent,
};

/// Shared application state accessible from all Tauri commands.
pub struct AppState {
    /// Raw PCM audio buffer (16kHz mono f32) accumulated during recording.
    pub audio_buffer: Arc<Mutex<Vec<f32>>>,
    /// Whether we are currently recording.
    pub is_recording: Arc<Mutex<bool>>,
    /// Handle to stop the audio stream (drop to stop).
    pub audio_stream_handle: Arc<Mutex<Option<cpal::Stream>>>,
    /// Parakeet transcription engine (loaded lazily on first use).
    pub transcriber: Arc<Mutex<Option<transcribe::TranscriptionEngine>>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            audio_buffer: Arc::new(Mutex::new(Vec::new())),
            is_recording: Arc::new(Mutex::new(false)),
            audio_stream_handle: Arc::new(Mutex::new(None)),
            transcriber: Arc::new(Mutex::new(None)),
        }
    }
}

fn setup_global_hotkey(app: &AppHandle) {
    use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

    // Option+Space as the default push-to-talk hotkey
    let shortcut: Shortcut = "Alt+Space".parse().expect("valid shortcut");

    let app_handle = app.clone();
    app.global_shortcut()
        .on_shortcut(shortcut, move |_app, _shortcut, event| {
            use tauri_plugin_global_shortcut::ShortcutState;
            match event.state {
                ShortcutState::Pressed => {
                    let _ = app_handle.emit("hotkey-pressed", ());
                    // Show the overlay window
                    if let Some(window) = app_handle.get_webview_window("overlay") {
                        let _ = window.show();
                        let _ = window.set_focus();
                        let _ = window.center();
                    }
                }
                ShortcutState::Released => {
                    let _ = app_handle.emit("hotkey-released", ());
                }
            }
        })
        .expect("failed to register global shortcut");
}

fn setup_tray(app: &AppHandle) {
    use tauri::menu::{MenuBuilder, MenuItemBuilder};

    let quit = MenuItemBuilder::with_id("quit", "Quit Aside").build(app).unwrap();
    let menu = MenuBuilder::new(app).item(&quit).build().unwrap();

    TrayIconBuilder::new()
        .menu(&menu)
        .on_menu_event(|app, event| {
            if event.id() == "quit" {
                app.exit(0);
            }
        })
        .tooltip("Aside")
        .build(app)
        .expect("failed to build tray icon");
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    env_logger::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            audio::start_recording,
            audio::stop_recording,
            transcribe::transcribe_audio,
            transcribe::load_model,
            context::get_active_context,
        ])
        .setup(|app| {
            setup_global_hotkey(app.handle());
            setup_tray(app.handle());
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app, event| {
            if let RunEvent::ExitRequested { api, .. } = event {
                // Keep running in background when window is closed
                api.prevent_exit();
            }
        });
}
