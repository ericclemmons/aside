import SwiftUI
import AsideCore

// MARK: - Settings Tab Enum

private enum SettingsTab: String, CaseIterable {
    case general
    case vocabulary

    var title: String {
        switch self {
        case .general: return "General"
        case .vocabulary: return "Vocabulary"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .vocabulary: return "text.book.closed"
        }
    }
}

// MARK: - Root View

struct SettingsView: View {
    @ObservedObject var whisperModelManager: WhisperModelManager
    @ObservedObject var parakeetModelManager: ParakeetModelManager
    @ObservedObject var customWordsManager: CustomWordsManager

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(
                        whisperModelManager: whisperModelManager,
                        parakeetModelManager: parakeetModelManager
                    )
                case .vocabulary:
                    VocabularySettingsView(customWordsManager: customWordsManager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18))
                            .frame(width: 28, height: 22)
                        Text(tab.title)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .frame(width: 68, height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

// MARK: - General Settings Tab

private struct GeneralSettingsView: View {
    @AppStorage(AppPreferenceKey.transcriptionEngine) private var engineRaw = TranscriptionEngine.dictation.rawValue
    @AppStorage(AppPreferenceKey.enhancementMode) private var enhancementModeRaw = EnhancementMode.off.rawValue
    @AppStorage(AppPreferenceKey.enhancementSystemPrompt) private var systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
    @AppStorage(AppPreferenceKey.hotkeyMode) private var hotkeyModeRaw = HotkeyMode.holdToTalk.rawValue

    @ObservedObject var whisperModelManager: WhisperModelManager
    @ObservedObject var parakeetModelManager: ParakeetModelManager

    private var selectedEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: engineRaw) ?? .dictation
    }

    private var selectedHotkeyMode: HotkeyMode {
        HotkeyMode(rawValue: hotkeyModeRaw) ?? .holdToTalk
    }

    private var appleIntelligenceAvailable: Bool {
        TextEnhancer.isAvailable
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: Transcription
                formRow("Transcription engine:") {
                    Picker("Engine", selection: $engineRaw) {
                        ForEach(TranscriptionEngine.allCases) { engine in
                            Text(engine.title).tag(engine.rawValue)
                        }
                    }
                    .labelsHidden()
                }

                if selectedEngine == .whisper {
                    formRow("Whisper model:") {
                        Picker("Model", selection: Binding(
                            get: { whisperModelManager.selectedVariant },
                            set: { whisperModelManager.selectedVariant = $0 }
                        )) {
                            ForEach(WhisperModelVariant.allCases) { variant in
                                Text("\(variant.title) (\(variant.sizeDescription))").tag(variant)
                            }
                        }
                        .labelsHidden()
                        .disabled(isWhisperBusy)
                    }

                    formRow("") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(whisperModelManager.selectedVariant.qualityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            whisperModelStatusRow
                        }
                    }
                }

                if selectedEngine == .parakeet {
                    formRow("") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Parakeet TDT 0.6B v3 — top-ranked accuracy, blazing fast. English only.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            parakeetModelStatusRow
                        }
                    }
                }

                sectionDivider()

                // MARK: Enhancement
                formRow("Text enhancement:") {
                    Picker("Enhancement", selection: $enhancementModeRaw) {
                        Text(EnhancementMode.off.title).tag(EnhancementMode.off.rawValue)
                        Text(EnhancementMode.appleIntelligence.title)
                            .tag(EnhancementMode.appleIntelligence.rawValue)
                    }
                    .labelsHidden()
                    .disabled(!appleIntelligenceAvailable)
                }

                if !appleIntelligenceAvailable {
                    formRow("") {
                        Label("Apple Intelligence is not available on this Mac.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if enhancementModeRaw == EnhancementMode.appleIntelligence.rawValue {
                    formRow("System prompt:") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextEditor(text: $systemPrompt)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(.quaternary.opacity(0.5))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .strokeBorder(.quaternary, lineWidth: 1)
                                )

                            HStack {
                                Text("Customise how Apple Intelligence enhances your transcriptions.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button("Reset to Default") {
                                    systemPrompt = AppPreferenceKey.defaultEnhancementPrompt
                                }
                                .controlSize(.small)
                                .disabled(systemPrompt == AppPreferenceKey.defaultEnhancementPrompt)
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(.top, 12)
        }
    }

    // MARK: - Whisper Model Status

    @ViewBuilder
    private var whisperModelStatusRow: some View {
        switch whisperModelManager.state {
        case .notDownloaded:
            HStack(spacing: 8) {
                Text("Not downloaded (\(whisperModelManager.selectedVariant.sizeDescription))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download") {
                    Task { await whisperModelManager.downloadModel() }
                }
                .controlSize(.small)
            }

        case .downloading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .frame(maxWidth: 140)
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

        case .downloaded:
            modelReadyRow(
                label: "Downloaded",
                sizeOnDisk: whisperModelManager.modelSizeOnDisk,
                onRemove: {
                    whisperModelManager.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
            )

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            modelReadyRow(
                label: "Ready",
                sizeOnDisk: whisperModelManager.modelSizeOnDisk,
                onRemove: {
                    whisperModelManager.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
            )

        case .error(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    whisperModelManager.deleteModel()
                    Task { await whisperModelManager.downloadModel() }
                }
                .controlSize(.small)
            }
        }
    }

    private var isWhisperBusy: Bool {
        switch whisperModelManager.state {
        case .downloading, .loading: return true
        default: return false
        }
    }

    // MARK: - Parakeet Model Status

    @ViewBuilder
    private var parakeetModelStatusRow: some View {
        switch parakeetModelManager.state {
        case .notDownloaded:
            HStack(spacing: 8) {
                Text("Not downloaded (~600 MB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Download") {
                    Task { await parakeetModelManager.downloadModel() }
                }
                .controlSize(.small)
            }

        case .downloading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .downloaded:
            modelReadyRow(
                label: "Downloaded",
                sizeOnDisk: parakeetModelManager.modelSizeOnDisk,
                onRemove: {
                    parakeetModelManager.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
            )

        case .loading:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            modelReadyRow(
                label: "Ready",
                sizeOnDisk: parakeetModelManager.modelSizeOnDisk,
                onRemove: {
                    parakeetModelManager.deleteModel()
                    engineRaw = TranscriptionEngine.dictation.rawValue
                }
            )

        case .error(let message):
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Retry") {
                    parakeetModelManager.deleteModel()
                    Task { await parakeetModelManager.downloadModel() }
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Shared Model Row

    private func modelReadyRow(label: String, sizeOnDisk: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Label {
                HStack(spacing: 4) {
                    Text(label)
                    if !sizeOnDisk.isEmpty {
                        Text("(\(sizeOnDisk))")
                            .foregroundStyle(.tertiary)
                    }
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Remove", role: .destructive) {
                onRemove()
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Vocabulary Tab

private struct VocabularySettingsView: View {
    @ObservedObject var customWordsManager: CustomWordsManager
    @State private var newWord: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Add word input
            HStack(spacing: 8) {
                TextField("Add a new word or phrase", text: $newWord)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        addCurrentWord()
                    }

                Button("Add") {
                    addCurrentWord()
                }
                .controlSize(.small)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            if customWordsManager.words.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 28))
                        .foregroundStyle(.quaternary)
                    Text("No custom words yet")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text("Add names, abbreviations, and specialised terms.\nAside will recognise them during transcription.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(customWordsManager.words.enumerated()), id: \.offset) { index, word in
                            wordRow(word, at: index)

                            if index < customWordsManager.words.count - 1 {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }

                Divider()

                HStack {
                    Text("\(customWordsManager.words.count) word\(customWordsManager.words.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func addCurrentWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customWordsManager.addWord(trimmed)
        newWord = ""
        isInputFocused = true
    }

    private func wordRow(_ word: String, at index: Int) -> some View {
        HStack {
            Text(word)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                customWordsManager.removeWord(at: index)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove word")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shared Form Helpers

private let formLabelWidth: CGFloat = 140

private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(label)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .frame(width: formLabelWidth, alignment: .trailing)

        content()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 4)
}

private func sectionDivider() -> some View {
    Divider()
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
}
