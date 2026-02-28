use serde::Serialize;
use std::process::Command;

#[derive(Debug, Serialize, Clone, Default)]
pub struct ActiveContext {
    pub app_name: String,
    pub window_title: String,
    pub url: Option<String>,
    pub selected_text: Option<String>,
}

/// Run an AppleScript snippet and return its stdout, trimmed.
fn run_applescript(script: &str) -> Option<String> {
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output()
        .ok()?;

    if output.status.success() {
        let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if text.is_empty() || text == "missing value" {
            None
        } else {
            Some(text)
        }
    } else {
        None
    }
}

/// Get the name of the frontmost application.
fn get_frontmost_app() -> Option<String> {
    run_applescript(
        r#"tell application "System Events" to get name of first application process whose frontmost is true"#,
    )
}

/// Get the window title of the frontmost application.
fn get_window_title() -> Option<String> {
    run_applescript(
        r#"tell application "System Events"
    set frontApp to first application process whose frontmost is true
    tell frontApp
        if (count of windows) > 0 then
            return name of front window
        end if
    end tell
end tell"#,
    )
}

/// Get the URL from a browser's active tab.
fn get_browser_url(app_name: &str) -> Option<String> {
    let script = match app_name {
        "Google Chrome" | "Brave Browser" | "Microsoft Edge" | "Chromium" | "Arc" => {
            format!(
                r#"tell application "{app_name}" to return URL of active tab of front window"#
            )
        }
        "Safari" | "Safari Technology Preview" => {
            format!(r#"tell application "{app_name}" to return URL of front document"#)
        }
        "Firefox" | "Firefox Developer Edition" => {
            // Firefox doesn't support AppleScript for URL access.
            // We'd need the accessibility API or an extension. Return None for now.
            return None;
        }
        _ => return None,
    };
    run_applescript(&script)
}

/// Get the currently selected text via Accessibility API.
fn get_selected_text() -> Option<String> {
    run_applescript(
        r#"tell application "System Events"
    set frontApp to first application process whose frontmost is true
    tell frontApp
        try
            set focusedElem to focused UI element
            return value of attribute "AXSelectedText" of focusedElem
        end try
    end tell
end tell"#,
    )
}

/// Check if we have Automation permission for System Events.
/// Runs a trivial AppleScript; if it fails, the user hasn't granted permission yet.
#[tauri::command]
pub fn check_automation() -> bool {
    run_applescript(r#"tell application "System Events" to return name of first application process whose frontmost is true"#).is_some()
}

/// Trigger the macOS Automation permission prompt by attempting an AppleScript call.
/// The OS will show the "wants to control System Events" dialog automatically.
/// Returns true if permission is already granted.
#[tauri::command]
pub fn request_automation() -> bool {
    run_applescript(r#"tell application "System Events" to return name of first application process whose frontmost is true"#).is_some()
}

/// Capture the active window context: app name, title, URL (if browser), selected text.
#[tauri::command]
pub fn get_active_context() -> ActiveContext {
    let app_name = get_frontmost_app().unwrap_or_default();
    let window_title = get_window_title().unwrap_or_default();
    let url = get_browser_url(&app_name);
    let selected_text = get_selected_text();

    log::info!(
        "Context captured: app={}, url={:?}, selected={}",
        app_name,
        url,
        selected_text.as_ref().map_or(0, |s| s.len())
    );

    ActiveContext {
        app_name,
        window_title,
        url,
        selected_text,
    }
}
