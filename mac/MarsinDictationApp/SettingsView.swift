import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showSaved = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("MarsinDictation")
                    .font(.title2)
                    .bold()
            }
            .padding(.bottom, 20)
            
            // Provider Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcription Provider")
                    .font(.headline)
                
                Picker("", selection: $settings.provider) {
                    Text("LocalAI (local, free)").tag("localai")
                    Text("OpenAI (cloud)").tag("openai")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.bottom, 16)
            
            Divider().padding(.bottom, 12)
            
            if settings.provider == "localai" {
                // LocalAI Settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("LocalAI")
                        .font(.headline)
                    
                    LabeledField(label: "Endpoint", text: $settings.localAIEndpoint,
                                placeholder: "http://localhost:3840")
                    
                    LabeledField(label: "Model", text: $settings.localAIModel,
                                placeholder: "whisper-large-turbo")
                }
                .padding(.bottom, 16)
            } else {
                // OpenAI Settings
                VStack(alignment: .leading, spacing: 10) {
                    Text("OpenAI")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        SecureField("sk-...", text: $settings.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("", selection: $settings.openAIModel) {
                            Text("gpt-4o-mini-transcribe").tag("gpt-4o-mini-transcribe")
                            Text("gpt-4o-transcribe").tag("gpt-4o-transcribe")
                            Text("whisper-1").tag("whisper-1")
                        }
                        .labelsHidden()
                    }
                }
                .padding(.bottom, 16)
            }
            
            Divider().padding(.bottom, 12)
            
            // Language
            VStack(alignment: .leading, spacing: 10) {
                Text("General")
                    .font(.headline)
                
                LabeledField(label: "Language (ISO 639-1)", text: $settings.language,
                            placeholder: "en")
            }
            .padding(.bottom, 16)
            
            Divider().padding(.bottom, 12)
            
            // Hotkeys (read-only)
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkeys")
                    .font(.headline)
                
                HStack {
                    Text("Dictation")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⌃⌥ Hold (Control+Option)")
                        .font(.system(.body, design: .monospaced))
                }
                
                HStack {
                    Text("Recovery")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("⌘⇧Z (Command+Shift+Z)")
                        .font(.system(.body, design: .monospaced))
                }
            }
            .padding(.bottom, 16)
            
            Spacer()
            
            // Status
            HStack {
                if showSaved {
                    Label("Settings saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                        .transition(.opacity)
                }
                Spacer()
                Text("Settings auto-save • API keys stored in Keychain")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420, height: 520)
        .onChange(of: settings.provider) { _ in flashSaved() }
        .onChange(of: settings.language) { _ in flashSaved() }
        .onChange(of: settings.localAIEndpoint) { _ in flashSaved() }
        .onChange(of: settings.localAIModel) { _ in flashSaved() }
        .onChange(of: settings.openAIModel) { _ in flashSaved() }
        .onChange(of: settings.openAIAPIKey) { _ in flashSaved() }
    }
    
    private func flashSaved() {
        withAnimation { showSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showSaved = false }
        }
    }
}

// MARK: - Labeled Text Field

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
