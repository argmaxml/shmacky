import Defaults
import SwiftUI

struct AISettingsPane: View {
  @Default(.aiModel) private var model
  @Default(.aiPrompt) private var prompt
  @Default(.aiThinking) private var thinking
  @Default(.aiTemperature) private var temperature
  @Default(.aiTopP) private var topP
  @Default(.aiTopK) private var topK
  @Default(.aiMinP) private var minP
  @Default(.aiPresencePenalty) private var presencePenalty
  @Default(.aiRepetitionPenalty) private var repetitionPenalty

  private var sampling: OllamaClient.SamplingOptions {
    OllamaClient.SamplingOptions(
      temperature: temperature, topP: topP, topK: topK, minP: minP,
      presencePenalty: presencePenalty, repetitionPenalty: repetitionPenalty
    )
  }

  private var preset: Binding<OllamaClient.SamplingPreset?> {
    Binding(
      get: {
        OllamaClient.SamplingPreset.allCases.first { $0.thinking == thinking && $0.options == sampling }
      },
      set: { if let preset = $0 { apply(preset) } }
    )
  }

  private func apply(_ preset: OllamaClient.SamplingPreset) {
    thinking = preset.thinking
    let values = preset.options
    temperature = values.temperature
    topP = values.topP
    topK = values.topK
    minP = values.minP
    presencePenalty = values.presencePenalty
    repetitionPenalty = values.repetitionPenalty
  }

  static var robotIcon: NSImage {
    let image = NSImage(size: NSSize(width: 24, height: 24))
    image.lockFocus()
    ("🤖" as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
    image.unlockFocus()
    image.accessibilityDescription = "AI"
    return image
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Text("Local Ollama").font(.headline)
        Text("Start Ollama with ‘ollama serve’. Shmacky connects to 127.0.0.1:11434.")
          .font(.caption)
          .foregroundStyle(.secondary)
        TextField("Model", text: $model)
          .accessibilityIdentifier("ai-model")
        Text("Use the name of an installed model from ‘ollama list’.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Picker("Preset", selection: preset) {
          ForEach(OllamaClient.SamplingPreset.allCases, id: \.self) { preset in
            Text(preset.title).tag(Optional(preset))
          }
          Text("Custom").tag(nil as OllamaClient.SamplingPreset?)
        }
        .accessibilityIdentifier("ai-sampling-preset")
        Toggle("Thinking mode", isOn: $thinking)
          .accessibilityIdentifier("ai-thinking")
        Text("Off by default for faster rewrites. Enable reasoning only with a model that supports thinking.")
          .font(.caption)
          .foregroundStyle(.secondary)
        samplingFields
        if !sampling.isValid {
          Text("One or more sampling values are out of range. Check the ranges in each field’s help text.")
            .font(.caption)
            .foregroundStyle(.red)
        }
        Button("Restore Paraphrasing Defaults") { apply(.instructGeneral) }
        Divider()
        Text("System prompt").font(.headline)
        TextEditor(text: $prompt)
          .font(.body)
          .frame(height: 180)
          .border(Color.secondary.opacity(0.3))
          .accessibilityLabel("System prompt")
          .accessibilityIdentifier("ai-prompt")
        Text("{clipboard} is replaced with the selected snippet’s full text. If omitted, the text is appended to the prompt.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Click 🤖 AI in the snippet toolbar to replace its content with a plain-text rewrite. Rich-text formatting is removed.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("Restore Default Prompt") { prompt = OllamaClient.defaultPrompt }
      }
      .padding()
    }
    .frame(width: 520, height: 660)
  }

  private var samplingFields: some View {
    Grid(horizontalSpacing: 20, verticalSpacing: 10) {
      GridRow {
        samplingField("Temperature", value: $temperature, id: "ai-temperature", help: "Range: 0–2")
        samplingField("Top P", value: $topP, id: "ai-top-p", help: "Range: 0–1")
      }
      GridRow {
        LabeledContent("Top K") {
          TextField("Top K", value: $topK, format: .number.grouping(.never))
            .textFieldStyle(.roundedBorder)
            .frame(width: 65)
            .accessibilityLabel("Top K")
            .accessibilityIdentifier("ai-top-k")
            .help("Non-negative integer; 0 disables top-k filtering.")
        }
        samplingField("Min P", value: $minP, id: "ai-min-p", help: "Range: 0–1")
      }
      GridRow {
        samplingField("Presence penalty", value: $presencePenalty,
                      id: "ai-presence-penalty", help: "Range: −2–2; 0 disables the penalty.")
        samplingField("Repetition penalty", value: $repetitionPenalty,
                      id: "ai-repetition-penalty", help: "Non-negative; 1 disables the penalty.")
      }
    }
  }

  private func samplingField(_ title: String, value: Binding<Double>, id: String, help: String) -> some View {
    LabeledContent(title) {
      TextField(title, value: value, format: .number.precision(.fractionLength(0...3)))
        .textFieldStyle(.roundedBorder)
        .frame(width: 65)
        .accessibilityLabel(title)
        .accessibilityIdentifier(id)
        .help(help)
    }
  }
}
