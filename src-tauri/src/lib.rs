mod audio;
mod context;
mod transcribe;

use parking_lot::Mutex;
use std::sync::Arc;
use tauri::{
    tray::TrayIconBuilder, Emitter, Manager, RunEvent,
};

use transcribe::SttBackend;

/// Wrapper to make cpal::Stream Send+Sync (it's only used behind a Mutex).
pub struct SendStream(#[allow(dead_code)] cpal::Stream);
unsafe impl Send for SendStream {}
unsafe impl Sync for SendStream {}

/// Shared application state accessible from all Tauri commands.
pub struct AppState {
    /// Raw PCM audio buffer (16kHz mono f32) accumulated during recording.
    pub audio_buffer: Arc<Mutex<Vec<f32>>>,
    /// Whether we are currently recording.
    pub is_recording: Arc<Mutex<bool>>,
    /// The actual sample rate of the recorded audio.
    pub audio_sample_rate: Arc<Mutex<u32>>,
    /// Handle to stop the audio stream (drop to stop).
    pub audio_stream_handle: Arc<Mutex<Option<SendStream>>>,
    /// Parakeet transcription engine (optional, requires --features parakeet).
    #[cfg(feature = "parakeet")]
    pub parakeet_engine: Arc<Mutex<Option<transcribe::ParakeetEngine>>>,
    /// Active STT backend.
    pub stt_backend: Arc<Mutex<SttBackend>>,
    /// Whether the hotkey listener has been started (prevents duplicates).
    pub hotkey_started: Arc<Mutex<bool>>,
}

impl Default for AppState {
    fn default() -> Self {
        Self {
            audio_buffer: Arc::new(Mutex::new(Vec::new())),
            is_recording: Arc::new(Mutex::new(false)),
            audio_sample_rate: Arc::new(Mutex::new(16000)),
            audio_stream_handle: Arc::new(Mutex::new(None)),
            #[cfg(feature = "parakeet")]
            parakeet_engine: Arc::new(Mutex::new(None)),
            stt_backend: Arc::new(Mutex::new(SttBackend::default())),
            hotkey_started: Arc::new(Mutex::new(false)),
        }
    }
}

/// Set up a CGEvent tap listening for the right Option key (press/release).
/// Runs on a background thread with its own CFRunLoop.
#[cfg(target_os = "macos")]
fn setup_right_option_hotkey(app_handle: tauri::AppHandle) {
    use core_foundation::runloop::CFRunLoop;
    use core_graphics::event::{
        CGEventTap, CGEventTapLocation, CGEventTapOptions, CGEventTapPlacement, CGEventType,
        EventField, KeyCode,
    };

    std::thread::spawn(move || {
        let handle = app_handle;
        let pressed = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let pressed_clone = pressed.clone();

        // Listen for FlagsChanged events (modifier keys fire this, not KeyDown/KeyUp)
        let tap = CGEventTap::new(
            CGEventTapLocation::Session,
            CGEventTapPlacement::HeadInsertEventTap,
            CGEventTapOptions::ListenOnly,
            vec![CGEventType::FlagsChanged],
            move |_proxy, _event_type, event| {
                let keycode =
                    event.get_integer_value_field(EventField::KEYBOARD_EVENT_KEYCODE) as u16;

                if keycode == KeyCode::RIGHT_OPTION {
                    let flags = event.get_flags();
                    let alt_down = flags
                        .contains(core_graphics::event::CGEventFlags::CGEventFlagAlternate);

                    let was_pressed =
                        pressed_clone.load(std::sync::atomic::Ordering::Relaxed);

                    if alt_down && !was_pressed {
                        pressed_clone.store(true, std::sync::atomic::Ordering::Relaxed);
                        let _ = handle.emit("hotkey-pressed", ());
                        log::info!("Right Option pressed");
                    } else if !alt_down && was_pressed {
                        pressed_clone.store(false, std::sync::atomic::Ordering::Relaxed);
                        let _ = handle.emit("hotkey-released", ());
                        log::info!("Right Option released");
                    }
                }

                // Pass event through unchanged (ListenOnly mode)
                None
            },
        );

        match tap {
            Ok(tap) => {
                tap.enable();
                let source = tap
                    .mach_port
                    .create_runloop_source(0)
                    .expect("failed to create runloop source");
                unsafe {
                    CFRunLoop::get_current().add_source(
                        &source,
                        core_foundation::runloop::kCFRunLoopCommonModes,
                    );
                }
                log::info!("Right Option hotkey listener active (CGEvent tap)");
                CFRunLoop::run_current();
            }
            Err(()) => {
                log::error!(
                    "Failed to create CGEvent tap — grant Accessibility permission in \
                     System Settings > Privacy & Security > Accessibility"
                );
            }
        }
    });
}

fn setup_tray(app: &tauri::AppHandle) {
    use tauri::menu::{CheckMenuItemBuilder, MenuBuilder, MenuItemBuilder, SubmenuBuilder};

    let quit = MenuItemBuilder::with_id("quit", "Quit Aside").build(app).unwrap();

    let parakeet_stt = CheckMenuItemBuilder::with_id("stt_parakeet", "Parakeet (NVIDIA)")
        .checked(true)
        .build(app)
        .unwrap();

    // Only show Apple Speech if SFSpeechRecognizer is available on this system
    let apple_available = unsafe { transcribe::speech_is_available_check() };

    let mut stt_submenu = SubmenuBuilder::with_id(app, "stt_backend", "STT Backend")
        .item(&parakeet_stt);

    let apple_stt = if apple_available {
        let item = CheckMenuItemBuilder::with_id("stt_apple", "Apple Speech")
            .checked(false)
            .build(app)
            .unwrap();
        stt_submenu = stt_submenu.item(&item);
        Some(item)
    } else {
        None
    };

    let stt_submenu = stt_submenu.build().unwrap();

    let menu = MenuBuilder::new(app)
        .item(&stt_submenu)
        .separator()
        .item(&quit)
        .build()
        .unwrap();

    let icon = tauri::image::Image::from_bytes(include_bytes!("../icons/tray-icon.png"))
        .expect("failed to load tray icon");

    TrayIconBuilder::new()
        .icon(icon)
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(move |app, event| {
            let id = event.id().as_ref();
            match id {
                "quit" => {
                    app.exit(0);
                }
                "stt_apple" => {
                    if let Some(ref a) = apple_stt { let _ = a.set_checked(true); }
                    let _ = parakeet_stt.set_checked(false);
                    let state = app.state::<AppState>();
                    *state.stt_backend.lock() = SttBackend::Apple;
                    log::info!("STT backend switched to Apple");
                }
                "stt_parakeet" => {
                    let _ = parakeet_stt.set_checked(true);
                    if let Some(ref a) = apple_stt { let _ = a.set_checked(false); }
                    let state = app.state::<AppState>();
                    *state.stt_backend.lock() = SttBackend::Parakeet;
                    log::info!("STT backend switched to Parakeet");
                }
                _ => {}
            }
        })
        .tooltip("Aside")
        .build(app)
        .expect("failed to build tray icon");
}

/// Check microphone permission status via AVCaptureDevice.
/// Returns "authorized", "denied", "restricted", or "not_determined".
#[tauri::command]
fn check_microphone() -> String {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        // Query TCC database directly — works for unbundled dev binaries
        let output = Command::new("sh")
            .args(["-c", "sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db \"SELECT auth_value FROM access WHERE service='kTCCServiceMicrophone' AND client='com.aside.app'\" 2>/dev/null"])
            .output();

        // Also try AVCaptureDevice via osascript as a fallback
        let av_output = Command::new("osascript")
            .args(["-e", "use framework \"AVFoundation\"
                set status to (current application's AVCaptureDevice's authorizationStatusForMediaType:(current application's AVMediaTypeAudio)) as integer
                return status as text"])
            .output();

        if let Ok(out) = av_output {
            let status_str = String::from_utf8_lossy(&out.stdout).trim().to_string();
            log::info!("Microphone AVCaptureDevice status: {status_str}");
            match status_str.as_str() {
                "0" => return "not_determined".into(),
                "1" => return "restricted".into(),
                "2" => return "denied".into(),
                "3" => return "authorized".into(),
                _ => {}
            }
        }

        if let Ok(out) = output {
            let val = String::from_utf8_lossy(&out.stdout).trim().to_string();
            log::info!("Microphone TCC status: {val}");
            match val.as_str() {
                "2" => return "authorized".into(),
                "0" => return "denied".into(),
                _ => {}
            }
        }

        "not_determined".into()
    }
    #[cfg(not(target_os = "macos"))]
    "authorized".into()
}

/// Request microphone permission via AVCaptureDevice.
/// Uses osascript to trigger the macOS system dialog.
#[tauri::command]
fn request_microphone() {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        // Use osascript to call AVCaptureDevice.requestAccess which triggers the system dialog
        let _ = Command::new("osascript")
            .args(["-e", "use framework \"AVFoundation\"
                current application's AVCaptureDevice's requestAccessForMediaType:(current application's AVMediaTypeAudio) completionHandler:(missing value)"])
            .spawn();
        log::info!("Microphone permission requested via osascript/AVCaptureDevice");
    }
}

/// Check if the app has Accessibility permission (required for CGEvent tap).
#[tauri::command]
fn check_accessibility() -> bool {
    #[cfg(target_os = "macos")]
    {
        extern "C" {
            fn AXIsProcessTrusted() -> bool;
        }
        unsafe { AXIsProcessTrusted() }
    }
    #[cfg(not(target_os = "macos"))]
    true
}

/// Prompt macOS to show the Accessibility permission dialog, returns current status.
#[tauri::command]
fn request_accessibility() -> bool {
    #[cfg(target_os = "macos")]
    {
        use core_foundation::base::TCFType;
        use core_foundation::boolean::CFBoolean;
        use core_foundation::dictionary::CFDictionary;
        use core_foundation::string::CFString;

        extern "C" {
            fn AXIsProcessTrustedWithOptions(
                options: core_foundation::base::CFTypeRef,
            ) -> bool;
        }

        let key = CFString::new("AXTrustedCheckOptionPrompt");
        let value = CFBoolean::true_value();
        let options = CFDictionary::from_CFType_pairs(&[(key, value)]);
        unsafe { AXIsProcessTrustedWithOptions(options.as_CFTypeRef()) }
    }
    #[cfg(not(target_os = "macos"))]
    true
}

/// Start the right-Option hotkey listener. Called from frontend after permissions are confirmed.
/// Only starts once — subsequent calls are no-ops.
#[tauri::command]
fn start_hotkey_listener(app: tauri::AppHandle, state: tauri::State<'_, AppState>) {
    #[cfg(target_os = "macos")]
    {
        // Prevent duplicate listeners (React StrictMode calls this twice)
        let mut started = state.hotkey_started.lock();
        if *started {
            log::info!("Hotkey listener already active, skipping duplicate start");
            return;
        }
        *started = true;
        setup_right_option_hotkey(app);
    }
}

/// Return the absolute path to the model directory.
/// Uses ~/Library/Application Support/com.aside.app/models/ to keep
/// large ONNX files out of the project tree (prevents Vite watcher from spinning).
#[tauri::command]
fn get_model_dir(name: String) -> Result<String, String> {
    let data_dir = dirs_next::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("com.aside.app")
        .join("models")
        .join(&name);
    log::info!("get_model_dir({name}) => {}", data_dir.display());
    Ok(data_dir.to_string_lossy().to_string())
}

/// Show + focus the overlay window.
/// `always_on_top`: true when invoked via hotkey, false during setup.
#[tauri::command]
fn show_overlay(app: tauri::AppHandle, always_on_top: Option<bool>) {
    if let Some(window) = app.get_webview_window("overlay") {
        let on_top = always_on_top.unwrap_or(true);
        let _ = window.set_always_on_top(on_top);
        let _ = window.show();
        let _ = window.set_focus();
        let _ = window.center();
    }
}

/// Resize the overlay window to fit content.
#[tauri::command]
fn resize_overlay(app: tauri::AppHandle, width: f64, height: f64) {
    if let Some(window) = app.get_webview_window("overlay") {
        let h = height.max(100.0).min(600.0); // clamp to reasonable range
        let _ = window.set_size(tauri::Size::Logical(tauri::LogicalSize { width, height: h }));
        let _ = window.center();
    }
}

/// Hide the overlay window.
#[tauri::command]
fn hide_overlay(app: tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("overlay") {
        let _ = window.set_always_on_top(false);
        let _ = window.hide();
    }
}

/// Start `opencode serve --port 4096` as a background process.
/// First checks that `opencode` exists in PATH; if not, shows a fatal dialog.
/// The server is spawned detached — if it's already running, the new process
/// will exit on its own (port conflict), which is fine.
fn start_opencode_server() {
    use std::process::{Command, Stdio};

    // Check that opencode is in PATH
    let which = Command::new("sh")
        .args(["-c", "command -v opencode"])
        .output();

    match which {
        Ok(output) if output.status.success() => {
            let path = String::from_utf8_lossy(&output.stdout);
            log::info!("Found opencode at {}", path.trim());
        }
        _ => {
            log::error!("opencode not found in PATH");
            show_fatal_dialog(
                "OpenCode is required but was not found.\n\n\
                 Install it and make sure `opencode` is in your PATH, then relaunch Aside.",
            );
        }
    }

    // Spawn the server in the background (don't wait for it)
    match Command::new("sh")
        .args(["-c", "opencode serve --port 4096"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(child) => {
            log::info!("opencode serve spawned (pid {})", child.id());
        }
        Err(e) => {
            log::error!("Failed to spawn opencode serve: {e}");
            show_fatal_dialog(&format!("Failed to start OpenCode server.\n\n{e}"));
        }
    }
}

/// Show a native macOS alert dialog and exit the process.
fn show_fatal_dialog(message: &str) {
    #[cfg(target_os = "macos")]
    {
        use std::process::Command;
        let script = format!(
            r#"display dialog "{}" with title "Aside" buttons {{"OK"}} default button "OK" with icon stop"#,
            message.replace('"', "\\\"").replace('\n', "\\n"),
        );
        let _ = Command::new("osascript").arg("-e").arg(&script).output();
    }
    std::process::exit(1);
}

fn setup_logging() {
    use log4rs::append::console::ConsoleAppender;
    use log4rs::append::file::FileAppender;
    use log4rs::config::{Appender, Root};
    use log4rs::encode::pattern::PatternEncoder;

    let log_path = dirs_next::data_local_dir()
        .unwrap_or_else(|| std::path::PathBuf::from("."))
        .join("com.aside.app")
        .join("aside.log");

    // Ensure parent dir exists
    if let Some(parent) = log_path.parent() {
        let _ = std::fs::create_dir_all(parent);
    }

    let pattern = "{d(%Y-%m-%d %H:%M:%S%.3f)} [{l}] {m}{n}";

    let stderr = ConsoleAppender::builder()
        .encoder(Box::new(PatternEncoder::new(pattern)))
        .build();

    let file = FileAppender::builder()
        .encoder(Box::new(PatternEncoder::new(pattern)))
        .build(&log_path)
        .expect("failed to create log file");

    let config = log4rs::Config::builder()
        .appender(Appender::builder().build("stderr", Box::new(stderr)))
        .appender(Appender::builder().build("file", Box::new(file)))
        .build(
            Root::builder()
                .appender("stderr")
                .appender("file")
                .build(log::LevelFilter::Info),
        )
        .expect("failed to build log config");

    log4rs::init_config(config).expect("failed to init logging");

    log::info!("Aside starting — log file: {}", log_path.display());
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    setup_logging();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        // Mic permission handled via our own check_microphone/request_microphone commands
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            audio::start_recording,
            audio::stop_recording,
            transcribe::transcribe_audio,
            transcribe::check_parakeet_model_exists,
            transcribe::load_parakeet_model,
            transcribe::set_stt_backend,
            transcribe::check_speech_available,
            transcribe::request_speech_auth,
            context::get_active_context,
            context::check_automation,
            context::request_automation,
            get_model_dir,
            check_microphone,
            request_microphone,
            check_accessibility,
            request_accessibility,
            start_hotkey_listener,
            show_overlay,
            resize_overlay,
            hide_overlay,
        ])
        .setup(|app| {
            // Hide dock icon — this is a menu bar / overlay-only app
            #[cfg(target_os = "macos")]
            app.handle().set_activation_policy(tauri::ActivationPolicy::Accessory)
                .expect("failed to set activation policy");

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
