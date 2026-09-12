// Why: BYOK (ADR-0007) means the user types their own AI service key here and it goes straight to
// the Keychain. The service is picked from presets (ADR-0018) so nobody has to know what a base
// URL is; the values behind a preset stay editable under 高级. Slice taste and 成片 look live only
// in their studios (ADR-0029). This screen also shows which on-device speech model is installed.

import LiveSliceASR
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var supportedLocales: [String] = []
    @State private var assetState: SpeechAssetState?
    @State private var downloadProgress: Double?
    @State private var message: String?
    @State private var showAdvanced = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("服务", selection: serviceSelection) {
                        ForEach(AIServicePreset.all) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                        Text("自定义").tag(AIServicePreset.customID)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "key.fill").foregroundStyle(StudioTheme.accent)
                        SecureField("粘贴 API 密钥", text: $keyDraft)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                    }
                    if let preset = settings.servicePreset {
                        Link(destination: preset.keyPage) {
                            LabeledContent {
                                Text(preset.name).foregroundStyle(StudioTheme.muted)
                            } label: {
                                Label("创建密钥", systemImage: "arrow.up.forward.square")
                            }
                        }
                    }
                    DisclosureGroup("高级", isExpanded: $showAdvanced) {
                        TextField("接口地址", text: $settings.baseURL)
                            .identifierField()
                        TextField("模型", text: $settings.model)
                            .identifierField()
                    }
                } header: {
                    Text("AI 服务")
                } footer: {
                    Text("转写在手机上完成，发给该服务的只有文字。密钥只存在本机钥匙串。")
                }
                Section("语音") {
                    Picker("语言", selection: $settings.localeIdentifier) {
                        Text("自动识别").tag(ASRLocalePreference.automaticIdentifier)
                        ForEach(supportedLocales, id: \.self) { identifier in
                            Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier)
                                .tag(identifier)
                        }
                    }
                    modelRow
                }
                if let message {
                    Section { Text(message).font(.footnote).textSelection(.enabled) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(StudioTheme.background)
            .navigationTitle("设置")
            .studioBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveAndClose() }
                }
            }
            .task { await loadSpeechInfo() }
            .onChange(of: settings.localeIdentifier) { _, _ in Task { await refreshAssetState() } }
            .onAppear { keyDraft = settings.apiKey }
        }
    }

    /// Reads the preset behind the stored endpoint; writing a preset applies it, writing 自定义
    /// keeps the current values and opens them for editing.
    private var serviceSelection: Binding<String> {
        Binding(
            get: {
                if let preset = settings.servicePreset { return preset.id }
                return AIServicePreset.customID
            },
            set: { id in
                if let preset = AIServicePreset.all.first(where: { $0.id == id }) {
                    settings.apply(preset)
                } else {
                    showAdvanced = true
                }
            }
        )
    }

    @ViewBuilder
    private var modelRow: some View {
        switch assetState {
        case .none:
            LabeledContent("语音模型", value: "查询中…")
        case .installed:
            LabeledContent("语音模型", value: "已安装")
        case .downloading:
            LabeledContent("语音模型", value: "系统正在下载")
        case .unsupported:
            LabeledContent("语音模型", value: "此设备不支持该语言")
        case .downloadable:
            if let downloadProgress {
                ProgressView(value: downloadProgress) { Text("下载语音模型") }
            } else {
                Button("下载语音模型") { Task { await downloadModel() } }
            }
        }
    }

    private func saveAndClose() {
        do {
            try settings.saveAPIKey(keyDraft)
            dismiss()
        } catch {
            message = "保存密钥失败：\(ErrorText.describe(error))"
        }
    }

    private func loadSpeechInfo() async {
        supportedLocales = await SpeechTranscriptionService.supportedLocaleIdentifiers()
        await refreshAssetState()
    }

    private func refreshAssetState() async {
        do {
            switch settings.localePreference {
            case .automatic:
                let locales = await SpeechLanguageDetector.candidateLocales()
                var states: [SpeechAssetState] = []
                for locale in locales {
                    states.append(try await SpeechTranscriptionService(locale: locale).assetState())
                }
                if states.isEmpty {
                    assetState = .unsupported
                } else if states.contains(.downloadable) || states.contains(.downloading) {
                    assetState = states.contains(.downloading) ? .downloading : .downloadable
                } else if states.allSatisfy({ $0 == .installed }) {
                    assetState = .installed
                } else {
                    assetState = .unsupported
                }
            case .fixed(let locale):
                assetState = try await SpeechTranscriptionService(locale: locale).assetState()
            }
        } catch {
            assetState = .unsupported
            message = ErrorText.describe(error)
        }
    }

    private func downloadModel() async {
        downloadProgress = 0
        do {
            try await SpeechTranscriptionService.installAssets(for: settings.localePreference) { value in
                Task { @MainActor in downloadProgress = value }
            }
            await refreshAssetState()
        } catch {
            message = "下载失败：\(ErrorText.describe(error))"
        }
        downloadProgress = nil
    }
}
