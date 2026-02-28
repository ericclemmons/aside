use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Instant;
use tauri::State;

use crate::AppState;

// --- Apple Speech (SFSpeechRecognizer) via swift-rs ---

swift_rs::swift!(fn speech_recognize_audio(
    audio_data: &swift_rs::SRData,
    sample_count: i64,
    sample_rate: i64
) -> swift_rs::SRString);

swift_rs::swift!(fn speech_is_available() -> bool);
swift_rs::swift!(fn speech_request_auth() -> bool);

fn transcribe_apple(audio: &[f32], sample_rate: u32) -> Result<TranscriptionResult, String> {
    let start = Instant::now();

    let byte_slice = unsafe {
        std::slice::from_raw_parts(audio.as_ptr() as *const u8, audio.len() * 4)
    };
    let sr_data: swift_rs::SRData = byte_slice.into();
    let sample_count = audio.len() as i64;
    let sr_sample_rate = sample_rate as i64;

    let result = unsafe { speech_recognize_audio(&sr_data, sample_count, sr_sample_rate) };
    let text = result.as_str().to_string();

    let duration_ms = start.elapsed().as_millis() as u64;

    if text.is_empty() {
        return Err("Apple Speech returned empty result (check microphone/permissions)".into());
    }

    Ok(TranscriptionResult { text, duration_ms })
}

// --- Parakeet engine (optional, behind feature flag) ---

#[cfg(feature = "parakeet")]
pub struct ParakeetEngine {
    model: parakeet_rs::Parakeet,
}

#[cfg(feature = "parakeet")]
unsafe impl Send for ParakeetEngine {}
#[cfg(feature = "parakeet")]
unsafe impl Sync for ParakeetEngine {}

#[cfg(feature = "parakeet")]
impl ParakeetEngine {
    pub fn new(model_dir: &str) -> Result<Self, String> {
        let model = parakeet_rs::Parakeet::from_pretrained(model_dir, None)
            .map_err(|e| format!("Failed to load Parakeet model: {e}"))?;
        Ok(Self { model })
    }

    pub fn transcribe(&mut self, audio: &[f32], sample_rate: u32) -> Result<TranscriptionResult, String> {
        use parakeet_rs::Transcriber;
        let start = Instant::now();
        let result = self.model
            .transcribe_samples(audio.to_vec(), sample_rate, 1, None)
            .map_err(|e| format!("Parakeet transcription failed: {e}"))?;
        let duration_ms = start.elapsed().as_millis() as u64;
        let text = clean_ctc_text(&result.text);
        if text.is_empty() {
            return Err("Parakeet returned empty result".into());
        }
        Ok(TranscriptionResult { text, duration_ms })
    }
}

// --- Shared types ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum SttBackend {
    Apple,
    Parakeet,
}

impl Default for SttBackend {
    fn default() -> Self {
        #[cfg(feature = "parakeet")]
        { Self::Parakeet }
        #[cfg(not(feature = "parakeet"))]
        { Self::Apple }
    }
}

#[derive(Debug, Serialize, Clone)]
pub struct TranscriptionResult {
    pub text: String,
    pub duration_ms: u64,
}

// --- Tauri commands ---

/// Check if the Parakeet model directory has the required files.
/// Only accepts `model_quantized.onnx` (int8) — other variants are
/// either too slow (fp16) or too inaccurate (q4).
#[tauri::command]
pub fn check_parakeet_model_exists(model_dir: String) -> bool {
    let dir = PathBuf::from(&model_dir);
    let has_tokenizer = dir.join("tokenizer.json").exists();
    let has_model = dir.join("model_quantized.onnx").exists();
    log::info!("check_parakeet_model_exists({model_dir}): tokenizer={has_tokenizer}, model={has_model}, cwd={:?}", std::env::current_dir());
    has_tokenizer && has_model
}

/// Clean up parakeet-rs CTC output.
/// The tokenizer uses "▁" to mark word starts, which decodes to a space.
/// Combined with parakeet-rs's `.join(" ")`, real word boundaries become
/// double spaces ("▁hello" + " " + "▁world" = " hello  world") while
/// subword continuations are single spaces ("▁test" + " " + "ing" = " test ing").
/// Split on double-space (word boundary), merge single spaces (subword joins).
fn clean_ctc_text(text: &str) -> String {
    text.split("  ")
        .map(|word| word.replace(' ', ""))
        .filter(|w| !w.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Simple linear-interpolation resample from `from_rate` to `to_rate`.
fn resample(audio: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
    if from_rate == to_rate {
        return audio.to_vec();
    }
    let ratio = from_rate as f64 / to_rate as f64;
    let out_len = (audio.len() as f64 / ratio) as usize;
    let mut out = Vec::with_capacity(out_len);
    for i in 0..out_len {
        let src_pos = i as f64 * ratio;
        let idx = src_pos as usize;
        let frac = src_pos - idx as f64;
        let s0 = audio[idx.min(audio.len() - 1)];
        let s1 = audio[(idx + 1).min(audio.len() - 1)];
        out.push(s0 + (s1 - s0) * frac as f32);
    }
    out
}

/// Transcribe the audio buffer using the active STT backend.
/// Runs on a blocking thread so it doesn't starve the Tauri async runtime.
#[tauri::command]
pub async fn transcribe_audio(state: State<'_, AppState>) -> Result<TranscriptionResult, String> {
    let (raw_audio, recorded_rate) = {
        let buf = state.audio_buffer.lock();
        if buf.is_empty() {
            return Err("No audio recorded".into());
        }
        let rate = *state.audio_sample_rate.lock();
        (buf.clone(), rate)
    };

    let backend = *state.stt_backend.lock();

    #[cfg(feature = "parakeet")]
    let engine_arc = state.parakeet_engine.clone();

    tauri::async_runtime::spawn_blocking(move || {
        // Resample to 16kHz if needed
        let audio = resample(&raw_audio, recorded_rate, 16000);
        log::info!("Resampled {}→16000Hz: {} → {} samples", recorded_rate, raw_audio.len(), audio.len());

        match backend {
            SttBackend::Apple => {
                log::info!("Transcribing with Apple SFSpeechRecognizer ({} samples)", audio.len());
                let result = transcribe_apple(&audio, 16000)?;
                log::info!(
                    "Apple STT completed in {}ms: '{}'",
                    result.duration_ms,
                    &result.text[..result.text.len().min(80)]
                );
                Ok(result)
            }
            SttBackend::Parakeet => {
                #[cfg(feature = "parakeet")]
                {
                    let mut engine_guard = engine_arc.lock();
                    let engine = engine_guard
                        .as_mut()
                        .ok_or("Parakeet model not loaded. Call load_parakeet_model first.")?;
                    log::info!("Transcribing with Parakeet ({} samples)", audio.len());
                    let result = engine.transcribe(&audio, 16000)?;
                    log::info!(
                        "Parakeet STT completed in {}ms: '{}'",
                        result.duration_ms,
                        &result.text[..result.text.len().min(80)]
                    );
                    Ok(result)
                }
                #[cfg(not(feature = "parakeet"))]
                Err("Parakeet support not compiled. Build with --features parakeet".into())
            }
        }
    })
    .await
    .map_err(|e| format!("Transcription task panicked: {e}"))?
}

/// Switch the active STT backend.
#[tauri::command]
pub fn set_stt_backend(backend: String, state: State<'_, AppState>) -> Result<(), String> {
    let new_backend = match backend.to_lowercase().as_str() {
        "apple" => SttBackend::Apple,
        "parakeet" => {
            #[cfg(not(feature = "parakeet"))]
            return Err("Parakeet support not compiled. Build with --features parakeet".into());
            #[cfg(feature = "parakeet")]
            SttBackend::Parakeet
        }
        other => return Err(format!("Unknown STT backend: '{other}'. Valid: apple, parakeet")),
    };
    *state.stt_backend.lock() = new_backend;
    log::info!("STT backend set to: {backend}");
    Ok(())
}

/// Load the Parakeet model from a directory path (requires --features parakeet).
#[tauri::command]
pub async fn load_parakeet_model(model_dir: String, state: State<'_, AppState>) -> Result<(), String> {
    #[cfg(feature = "parakeet")]
    {
        let path = PathBuf::from(&model_dir);
        if !path.exists() {
            return Err(format!("Model directory not found: {model_dir} (cwd: {:?})", std::env::current_dir()));
        }
        let engine_arc = state.parakeet_engine.clone();
        tauri::async_runtime::spawn_blocking(move || {
            log::info!("Loading Parakeet model from {model_dir}...");
            let engine = ParakeetEngine::new(&model_dir)?;
            *engine_arc.lock() = Some(engine);
            log::info!("Parakeet model loaded from {model_dir}");
            Ok::<(), String>(())
        })
        .await
        .map_err(|e| format!("Model load task panicked: {e}"))?
    }
    #[cfg(not(feature = "parakeet"))]
    {
        let _ = (model_dir, state);
        Err("Parakeet support not compiled. Build with --features parakeet".into())
    }
}

/// Check if Apple Speech Recognition is available (safe to call, won't crash).
pub unsafe fn speech_is_available_check() -> bool {
    speech_is_available()
}

/// Check if Apple Speech Recognition is available.
#[tauri::command]
pub fn check_speech_available() -> bool {
    unsafe { speech_is_available() }
}

/// Request speech recognition authorization from the user.
#[tauri::command]
pub fn request_speech_auth() -> bool {
    unsafe { speech_request_auth() }
}
