import Foundation
import Testing
@testable import Maccy

@Suite(.serialized)
struct OllamaClientTests {
  @Test func substitutesClipboardLiterally() {
    #expect(OllamaClient.expandedPrompt("Rewrite: {clipboard}", clipboard: "Hello {clipboard}")
            == "Rewrite: Hello {clipboard}")
    #expect(OllamaClient.expandedPrompt("Rewrite", clipboard: "Hello") == "Rewrite\nHello")
  }

  @Test func requestContainsFullTextAndDisablesStreaming() throws {
    let text = String(repeating: "Message\n", count: 4000)
    let data = try JSONEncoder().encode(OllamaClient.Request(
      model: "local-model", prompt: OllamaClient.expandedPrompt(OllamaClient.defaultPrompt, clipboard: text)
    ))
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["model"] as? String == "local-model")
    #expect(json["stream"] as? Bool == false)
    #expect(json["think"] as? Bool == false)
    #expect((json["prompt"] as? String)?.hasSuffix(text) == true)
  }

  @Test(arguments: [false, true])
  func requestIncludesThinkingSetting(thinking: Bool) throws {
    let request = OllamaClient.Request(model: "local-model", prompt: "Rewrite this", think: thinking)
    let data = try JSONEncoder().encode(request)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["think"] as? Bool == thinking)
  }

  @Test func defaultSamplingMatchesParaphrasingRecommendation() throws {
    let data = try JSONEncoder().encode(OllamaClient.Request(model: "model", prompt: "text"))
    let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let options = try #require(request["options"] as? [String: Double])
    #expect(options == ["temperature": 0.7, "top_p": 0.8, "top_k": 20, "min_p": 0,
                        "presence_penalty": 1.5, "repeat_penalty": 1])
    #expect(request["think"] as? Bool == false)
    #expect(options["repetition_penalty"] == nil)
  }

  @Test func presetsMatchRecommendations() {
    let presets = OllamaClient.SamplingPreset.allCases
    #expect(presets.map(\.thinking) == [false, true, true, false])
    #expect(presets.map { $0.options.temperature } == [0.7, 1, 0.6, 1])
    #expect(presets.map { $0.options.topP } == [0.8, 0.95, 0.95, 0.95])
    #expect(presets.map { $0.options.presencePenalty } == [1.5, 1.5, 0, 1.5])
    for preset in presets {
      #expect(preset.options.topK == 20)
      #expect(preset.options.minP == 0)
      #expect(preset.options.repetitionPenalty == 1)
      #expect(preset.options.isValid)
    }
  }

  @Test func forwardsCustomSamplingToOllama() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OllamaMockProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    OllamaMockProtocol.status = 200
    OllamaMockProtocol.body = #"{"response":"Rewritten","done":true}"#
    OllamaMockProtocol.requestBody = nil
    let options = OllamaClient.SamplingOptions(
      temperature: 0.4, topP: 0.9, topK: 35, minP: 0.1, presencePenalty: 0.2, repetitionPenalty: 1.1
    )
    _ = try await OllamaClient(session: session).rewrite(
      "Original", model: "model", template: "Rewrite {clipboard}", think: true, options: options
    )
    let data = try #require(OllamaMockProtocol.requestBody)
    let request = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(request["think"] as? Bool == true)
    #expect(request["options"] as? [String: Double] == [
      "temperature": 0.4, "top_p": 0.9, "top_k": 35, "min_p": 0.1,
      "presence_penalty": 0.2, "repeat_penalty": 1.1
    ])
  }

  @Test func rejectsInvalidSamplingBeforeSending() async {
    let invalid: [OllamaClient.SamplingOptions] = [
      .init(temperature: -1), .init(temperature: .nan), .init(temperature: 2.1),
      .init(topP: 1.1), .init(topK: -1), .init(minP: -0.1),
      .init(presencePenalty: 2.1), .init(repetitionPenalty: -1), .init(repetitionPenalty: .infinity)
    ]
    for options in invalid {
      do {
        _ = try await OllamaClient().rewrite("Text", model: "model", template: "Rewrite", options: options)
        Issue.record("Invalid sampling should not be sent")
      } catch {
        #expect(error.localizedDescription.contains("sampling parameters"))
      }
    }
  }

  @Test func responseHandling() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [OllamaMockProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let client = OllamaClient(session: session)
    let cases: [(Int, String, String?)] = [
      (200, #"{"response":"  Rewritten message.\n","done":true}"#, "Rewritten message."),
      (200, #"{"response":"","done":true}"#, nil),
      (200, #"{"response":"partial","done":false}"#, nil),
      (200, #"{"response":"partial","done":true,"done_reason":"length"}"#, nil),
      (404, #"{"error":"model not found"}"#, nil),
      (500, "server failed", nil),
      (200, "not JSON", nil)
    ]
    for (status, body, expected) in cases {
      OllamaMockProtocol.status = status
      OllamaMockProtocol.body = body
      do {
        let result = try await client.rewrite("Hello", model: "local-model", template: "Rewrite {clipboard}")
        #expect(result == expected)
      } catch {
        #expect(expected == nil)
      }
    }
  }

  @Test func emptyModelIsRejected() async {
    do {
      _ = try await OllamaClient().rewrite("Hello", model: "  ", template: "Rewrite")
      Issue.record("An empty model should be rejected before sending a request")
    } catch {
      #expect(error.localizedDescription.contains("Choose an Ollama model"))
    }
  }
}

private final class OllamaMockProtocol: URLProtocol, @unchecked Sendable {
  // Only accessed by the serialized suite, one request at a time.
  nonisolated(unsafe) static var status = 200
  nonisolated(unsafe) static var body = ""
  nonisolated(unsafe) static var requestBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requestBody = request.httpBody
    if Self.requestBody == nil, let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var data = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(contentsOf: buffer.prefix(count))
      }
      Self.requestBody = data
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                   httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
