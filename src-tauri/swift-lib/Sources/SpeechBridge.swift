import Foundation
import SwiftRs
import AVFoundation
import Speech

/// Recognize speech from raw f32 PCM audio using Apple's SFSpeechRecognizer.
/// Runs recognition on a background queue to avoid blocking the main thread.
/// Returns: transcribed text, or empty string on failure.
@_cdecl("speech_recognize_audio")
public func speechRecognizeAudio(
    audioData: SRData,
    sampleCount: Int,
    sampleRate: Int
) -> SRString {
    let semaphore = DispatchSemaphore(value: 0)
    var resultText = ""
    var didSignal = false
    let signalOnce = { () -> Void in
        if !didSignal {
            didSignal = true
            semaphore.signal()
        }
    }

    // Run on a background queue so the semaphore doesn't block the main run loop
    DispatchQueue.global(qos: .userInitiated).async {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            NSLog("SFSpeechRecognizer not available for en-US")
            signalOnce()
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false

        if #available(macOS 13.0, *) {
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
        }

        // Convert raw f32 bytes to AVAudioPCMBuffer
        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!

        let frameCount = AVAudioFrameCount(sampleCount)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount) else {
            NSLog("Failed to create AVAudioPCMBuffer")
            signalOnce()
            return
        }
        pcmBuffer.frameLength = frameCount

        let rawBytes = audioData.toArray()
        rawBytes.withUnsafeBufferPointer { bytesPtr in
            guard let channelData = pcmBuffer.floatChannelData?[0] else { return }
            bytesPtr.baseAddress!.withMemoryRebound(to: Float32.self, capacity: sampleCount) { floatPtr in
                channelData.update(from: floatPtr, count: sampleCount)
            }
        }

        request.append(pcmBuffer)
        request.endAudio()

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error = error {
                NSLog("SFSpeechRecognizer error: \(error.localizedDescription)")
                signalOnce()
                return
            }
            if let result = result, result.isFinal {
                resultText = result.bestTranscription.formattedString
                signalOnce()
            }
        }

        // Timeout on the background queue
        let deadline = DispatchTime.now() + .seconds(15)
        if semaphore.wait(timeout: deadline) == .timedOut {
            NSLog("SFSpeechRecognizer timed out after 15s")
            task.cancel()
            signalOnce()
        }
    }

    // Wait for the background queue to finish
    semaphore.wait()
    return SRString(resultText)
}

/// Check if speech recognition is available (permission + recognizer + model).
@_cdecl("speech_is_available")
public func speechIsAvailable() -> Bool {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
        return false
    }
    return recognizer.isAvailable
}

/// Request speech recognition authorization. Returns true if authorized.
@_cdecl("speech_request_auth")
public func speechRequestAuth() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var authorized = false

    SFSpeechRecognizer.requestAuthorization { status in
        authorized = (status == .authorized)
        semaphore.signal()
    }

    _ = semaphore.wait(timeout: .now() + .seconds(30))
    return authorized
}
