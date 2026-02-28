use parakeet_rs::ParakeetTDT;
use serde::Serialize;
use std::time::Instant;
use tauri::State;

use crate::AppState;

/// Wraps the Parakeet TDT model for transcription.
pub struct TranscriptionEngine {
    model: ParakeetTDT,
}

impl TranscriptionEngine {
    pub fn new(model_dir: &str) -> Result<Self, String> {
        let model =
            ParakeetTDT::from_pretrained(model_dir, None).map_err(|e| format!("Failed to load Parakeet model: {e}"))?;
        Ok(Self { model })
    }

    pub fn transcribe(&self, audio: Vec<f32>, sample_rate: u32) -> Result<TranscriptionResult, String> {
        let start = Instant::now();

        let result = self
            .model
            .transcribe_samples(audio, sample_rate, 1, None)
            .map_err(|e| format!("Transcription failed: {e}"))?;

        let duration_ms = start.elapsed().as_millis() as u64;

        Ok(TranscriptionResult {
            text: result.text,
            duration_ms,
        })
    }
}

#[derive(Debug, Serialize, Clone)]
pub struct TranscriptionResult {
    pub text: String,
    pub duration_ms: u64,
}

/// Load the Parakeet model from a directory. Call once on startup or first use.
#[tauri::command]
pub fn load_model(model_dir: String, state: State<'_, AppState>) -> Result<(), String> {
    let engine = TranscriptionEngine::new(&model_dir)?;
    *state.transcriber.lock() = Some(engine);
    log::info!("Parakeet model loaded from {model_dir}");
    Ok(())
}

/// Transcribe the audio buffer captured during the last recording session.
#[tauri::command]
pub fn transcribe_audio(state: State<'_, AppState>) -> Result<TranscriptionResult, String> {
    let audio = {
        let buf = state.audio_buffer.lock();
        if buf.is_empty() {
            return Err("No audio recorded".into());
        }
        buf.clone()
    };

    let transcriber = state.transcriber.lock();
    let engine = transcriber
        .as_ref()
        .ok_or("Model not loaded. Call load_model first.")?;

    // Transcribe on the current thread (Tauri runs commands on a thread pool)
    let result = engine.transcribe(audio, 16000)?;
    log::info!(
        "Transcription completed in {}ms: '{}'",
        result.duration_ms,
        &result.text[..result.text.len().min(80)]
    );

    Ok(result)
}
