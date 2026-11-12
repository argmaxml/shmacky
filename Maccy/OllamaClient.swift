import Foundation

nonisolated struct OllamaClient {
  static let defaultPrompt =
    "Given the following email or message to be sent, please check for spelling or grammar mistakes, "
    + "make it American business friendly and rewrite the message. "
    + "Write only the paraphrased message. \n {clipboard}"

  /// Ollama calls Qwen's repetition_penalty option repeat_penalty on the wire.
  struct SamplingOptions: Encodable, Equatable, Sendable {
    var temperature = 0.7
    var topP = 0.8
    var topK = 20
    var minP = 0.0
    var presencePenalty = 1.5
    var repetitionPenalty = 1.0

    enum CodingKeys: String, CodingKey {
      case temperature
      case topP = "top_p"
      case topK = "top_k"
      case minP = "min_p"
      case presencePenalty = "presence_penalty"
      case repetitionPenalty = "repeat_penalty"
    }

    var isValid: Bool {
      temperature.isFinite && (0...2).contains(temperature)
        && topP.isFinite && (0...1).contains(topP)
        && topK >= 0
        && minP.isFinite && (0...1).contains(minP)
        && presencePenalty.isFinite && (-2...2).contains(presencePenalty)
        && repetitionPenalty.isFinite && repetitionPenalty >= 0
    }
  }

  enum SamplingPreset: String, CaseIterable, Sendable {
    case instructGeneral, thinkingGeneral, thinkingCoding, instructReasoning

    var title: String {
      switch self {
      case .instructGeneral: "Instruct — General / paraphrasing (default)"
      case .thinkingGeneral: "Thinking — General tasks"
      case .thinkingCoding: "Thinking — Precise coding"
      case .instructReasoning: "Instruct — Reasoning tasks"
      }
    }

    var thinking: Bool { self == .thinkingGeneral || self == .thinkingCoding }

    var options: SamplingOptions {
      switch self {
      case .instructGeneral: SamplingOptions()
      case .thinkingGeneral, .instructReasoning: SamplingOptions(temperature: 1.0, topP: 0.95)
      case .thinkingCoding: SamplingOptions(temperature: 0.6, topP: 0.95, presencePenalty: 0.0)
      }
    }
  }

  struct Request: Encodable {
    let model: String
    let prompt: String
    let stream = false
    var think = false
    var options = SamplingOptions()
  }

  struct Response: Decodable {
    let response: String
    let done: Bool
    let done_reason: String?
  }

  struct ServerError: Decodable {
    let error: String
  }

  enum Failure: LocalizedError {
    case message(String)

    var errorDescription: String? {
      switch self {
      case .message(let message): return message
      }
    }
  }

  var session: URLSession = .shared

  static func expandedPrompt(_ template: String, clipboard: String) -> String {
    if template.contains("{clipboard}") {
      return template.replacingOccurrences(of: "{clipboard}", with: clipboard)
    }
    return template + "\n" + clipboard
  }

  func rewrite(
    _ text: String, model: String, template: String, think: Bool = false,
    options: SamplingOptions = SamplingOptions()
  ) async throws -> String {
    let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !model.isEmpty else { throw Failure.message("Choose an Ollama model in Settings → AI.") }
    guard options.isValid else {
      throw Failure.message("Check the sampling parameters in Settings → AI. One or more values are out of range.")
    }
    var request = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/generate")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(Request(
      model: model, prompt: Self.expandedPrompt(template, clipboard: text), think: think, options: options
    ))
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost {
      throw Failure.message("Cannot connect to local Ollama. Start it with ‘ollama serve’, then try again.")
    }
    guard let http = response as? HTTPURLResponse else {
      throw Failure.message("Ollama returned an invalid response.")
    }
    guard (200..<300).contains(http.statusCode) else {
      let detail = (try? JSONDecoder().decode(ServerError.self, from: data))?.error
      throw Failure.message(detail ?? "Ollama request failed (HTTP \(http.statusCode)).")
    }
    let result = try JSONDecoder().decode(Response.self, from: data)
    guard result.done, result.done_reason != "length" else {
      throw Failure.message("Ollama did not finish the rewrite. The original snippet was kept.")
    }
    let rewritten = result.response.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rewritten.isEmpty else {
      throw Failure.message("Ollama returned an empty rewrite. The original snippet was kept.")
    }
    return rewritten
  }
}
