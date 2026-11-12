import AppKit
import Defaults
import Observation

@MainActor
@Observable
final class AIRewriteController {
  static let shared = AIRewriteController()

  private(set) var isRewriting = false
  var errorMessage: String?

  func rewrite(_ item: HistoryItemDecorator) {
    guard !isRewriting else { return }
    let historyItem = item.item
    let original = historyItem.previewableText
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let originalContents = historyItem.contents.map { ($0.type, $0.value) }
    let model = Defaults[.aiModel]
    let prompt = Defaults[.aiPrompt]
    let thinking = Defaults[.aiThinking]
    let sampling = OllamaClient.SamplingOptions(
      temperature: Defaults[.aiTemperature], topP: Defaults[.aiTopP], topK: Defaults[.aiTopK],
      minP: Defaults[.aiMinP], presencePenalty: Defaults[.aiPresencePenalty],
      repetitionPenalty: Defaults[.aiRepetitionPenalty]
    )
    isRewriting = true
    errorMessage = nil

    Task {
      defer { isRewriting = false }
      do {
        let rewritten = try await OllamaClient().rewrite(
          original, model: model, template: prompt, think: thinking, options: sampling
        )
        // Selection may change during generation. Only update the original, still-existing snippet.
        guard History.shared.items.contains(where: { $0.item === historyItem }),
              historyItem.contents.count == originalContents.count,
              zip(historyItem.contents, originalContents).allSatisfy({ content, saved in
                content.type == saved.0 && content.value == saved.1
              }) else {
          throw OllamaClient.Failure.message("The snippet was edited or deleted during the rewrite. No changes were made.")
        }
        let oldContents = historyItem.contents
        let oldTitle = historyItem.title
        let usesGeneratedTitle = oldTitle.isEmpty || oldTitle == historyItem.generateTitle()
        let replacement = HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue,
                                             value: Data(rewritten.utf8))
        historyItem.contents = [replacement]
        if usesGeneratedTitle { historyItem.title = historyItem.generateTitle() }
        do {
          try Storage.shared.context.save()
        } catch {
          historyItem.contents = oldContents
          historyItem.title = oldTitle
          Storage.shared.context.delete(replacement)
          throw error
        }
        // Old rich-text representations must not override the rewritten plain text when pasted.
        oldContents.forEach(Storage.shared.context.delete)
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
