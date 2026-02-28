fn main() {
    #[cfg(target_os = "macos")]
    {
        swift_rs::SwiftLinker::new("10.15")
            .with_package("swift-lib", "./swift-lib/")
            .link();

        // Weakly link Speech framework so it doesn't trigger TCC at load time.
        // Without this, macOS kills the process immediately if
        // NSSpeechRecognitionUsageDescription is missing from Info.plist
        // (which happens in dev builds where there's no .app bundle).
        println!("cargo:rustc-link-arg=-weak_framework");
        println!("cargo:rustc-link-arg=Speech");

        // AVFoundation for AVCaptureDevice microphone permission checks
        println!("cargo:rustc-link-lib=framework=AVFoundation");
    }

    tauri_build::build()
}
