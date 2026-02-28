use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, Stream, StreamConfig};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, State};

use crate::AppState;

/// Build a cpal input stream that captures 16kHz mono f32 audio.
fn build_input_stream(
    app: AppHandle,
    buffer: Arc<parking_lot::Mutex<Vec<f32>>>,
    is_recording: Arc<parking_lot::Mutex<bool>>,
    sample_rate_out: Arc<parking_lot::Mutex<u32>>,
) -> Result<Stream, String> {
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or("No input device available")?;

    log::info!("Using input device: {}", device.name().unwrap_or_default());

    // Try to get a config close to 16kHz mono f32.
    // macOS may provide 48kHz — we'll resample later or ask for 16kHz.
    let supported = device
        .supported_input_configs()
        .map_err(|e| format!("Failed to query input configs: {e}"))?;

    let config = supported
        .filter(|c| c.sample_format() == SampleFormat::F32)
        .min_by_key(|c| {
            // Prefer configs closest to 16kHz mono
            let rate_diff = (c.min_sample_rate().0 as i64 - 16000).abs();
            let ch_diff = (c.channels() as i64 - 1).abs();
            rate_diff + ch_diff * 10000
        })
        .ok_or("No suitable input config found")?;

    let sample_rate = if config.min_sample_rate().0 <= 16000 && config.max_sample_rate().0 >= 16000
    {
        cpal::SampleRate(16000)
    } else {
        config.min_sample_rate()
    };

    let stream_config = StreamConfig {
        channels: config.channels(),
        sample_rate,
        buffer_size: cpal::BufferSize::Default,
    };

    let channels = stream_config.channels as usize;
    let actual_rate = stream_config.sample_rate.0;

    // Store actual sample rate for resampling later
    *sample_rate_out.lock() = actual_rate;

    log::info!(
        "Audio config: {}Hz, {} channels",
        actual_rate,
        channels
    );

    // For waveform: emit RMS amplitude at ~30fps
    let emit_interval = (actual_rate as usize) / 30; // samples per emit
    let mut sample_count = 0usize;
    let mut rms_accum = 0.0f64;
    let mut rms_samples = 0usize;
    let mut emit_count = 0u64;

    let stream = device
        .build_input_stream(
            &stream_config,
            move |data: &[f32], _info: &cpal::InputCallbackInfo| {
                if !*is_recording.lock() {
                    return;
                }

                let mut buf = buffer.lock();

                // If multi-channel, mix down to mono
                for chunk in data.chunks(channels) {
                    let mono: f32 =
                        chunk.iter().sum::<f32>() / channels as f32;
                    buf.push(mono);

                    rms_accum += (mono as f64) * (mono as f64);
                    rms_samples += 1;
                    sample_count += 1;

                    if sample_count >= emit_interval {
                        let rms = if rms_samples > 0 {
                            (rms_accum / rms_samples as f64).sqrt()
                        } else {
                            0.0
                        };
                        // Emit amplitude level for waveform visualization
                        emit_count += 1;
                        if emit_count % 30 == 0 {
                            log::info!("audio-level RMS={:.6} (max_sample={:.4})", rms,
                                data.iter().map(|s| s.abs()).fold(0.0f32, f32::max));
                        }
                        let _ = app.emit("audio-level", rms);
                        rms_accum = 0.0;
                        rms_samples = 0;
                        sample_count = 0;
                    }
                }
            },
            |err| {
                log::error!("Audio stream error: {err}");
            },
            None,
        )
        .map_err(|e| format!("Failed to build input stream: {e}"))?;

    stream.play().map_err(|e| format!("Failed to start stream: {e}"))?;

    Ok(stream)
}

#[tauri::command]
pub fn start_recording(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    // Prevent duplicate starts
    if *state.is_recording.lock() {
        log::info!("Already recording, ignoring duplicate start");
        return Ok(());
    }

    // Clear the buffer
    state.audio_buffer.lock().clear();
    *state.is_recording.lock() = true;

    // Build and store the stream
    let stream = build_input_stream(
        app,
        state.audio_buffer.clone(),
        state.is_recording.clone(),
        state.audio_sample_rate.clone(),
    )?;
    *state.audio_stream_handle.lock() = Some(crate::SendStream(stream));

    log::info!("Recording started");
    Ok(())
}

#[tauri::command]
pub fn stop_recording(state: State<'_, AppState>) -> Result<usize, String> {
    // Prevent duplicate stops
    if !*state.is_recording.lock() {
        let sample_count = state.audio_buffer.lock().len();
        log::info!("Already stopped, ignoring duplicate stop ({} samples)", sample_count);
        return Ok(sample_count);
    }

    *state.is_recording.lock() = false;

    // Drop the stream to stop capturing
    *state.audio_stream_handle.lock() = None;

    let sample_count = state.audio_buffer.lock().len();
    log::info!("Recording stopped: {} samples captured", sample_count);
    Ok(sample_count)
}
