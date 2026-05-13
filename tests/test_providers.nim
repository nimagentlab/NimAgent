## test_providers.nim
## Unit tests for LLM providers: base methods, OpenAI specifics, Ollama specifics.

import std/[asyncdispatch, unittest, json, sequtils]
import nimagent/providers/base
import nimagent/providers/openai_compatible
import nimagent/providers/ollama
import nimagent/messages
import nimagent/utils/json_compat
import nimagent/utils/async_compat

# =============================================================================
# Mock Providers
# =============================================================================

type
  MockProvider = ref object of LLMProvider
    responses: seq[Message]
    callIndex: int
    embedResponse: seq[float]

  FailingEmbeddingProvider = ref object of LLMProvider

method generate*(p: MockProvider, messages: seq[Message],
    toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let idx = p.callIndex
  p.callIndex += 1
  if idx < p.responses.len:
    return p.responses[idx]
  return Message(role: Assistant, content: "Default")

method getEmbedding*(p: MockProvider, text: string): Future[seq[float]] {.async.} =
  return p.embedResponse

method countTokens*(p: MockProvider, text: string): int =
  return text.len div 4

method getMaxContextTokens*(p: MockProvider): Future[int] {.async.} =
  return 8192

method supportsTools*(p: MockProvider): bool =
  return true

method supportsVision*(p: MockProvider): bool =
  return false

method isAlive*(p: MockProvider): Future[bool] {.async.} =
  return true

method getAvailableModels*(p: MockProvider): Future[seq[string]] {.async.} =
  return @[]

method getEmbedding*(p: FailingEmbeddingProvider, text: string): Future[seq[float]] {.async.} =
  raise newException(IOError, "embedding service unavailable")

proc newMockProvider(responses: seq[Message] = @[],
                     embedResponse: seq[float] = @[]): MockProvider =
  MockProvider(responses: responses, callIndex: 0, embedResponse: embedResponse)

# =============================================================================
# Base Provider
# =============================================================================

suite "Base Provider":
  test "generate returns preset response":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "Hello from mock")
    ])
    let result = waitFor provider.generate(@[])
    check result.content == "Hello from mock"

  test "countTokens fallback is text.len div 4":
    let provider = newMockProvider()
    check provider.countTokens("abcd") == 1
    check provider.countTokens("abcdefgh") == 2

  test "getMaxContextTokens fallback is 8192":
    let provider = newMockProvider()
    let max = waitFor provider.getMaxContextTokens()
    check max == 8192

  test "supportsTools default is true":
    let provider = newMockProvider()
    check provider.supportsTools() == true

  test "supportsVision default is false":
    let provider = newMockProvider()
    check provider.supportsVision() == false

  test "isAlive default is true":
    let provider = newMockProvider()
    let alive = waitFor provider.isAlive()
    check alive == true

  test "getAvailableModels default is empty":
    let provider = newMockProvider()
    let models = waitFor provider.getAvailableModels()
    check models.len == 0

  test "safeGetEmbedding returns embedding on success":
    let provider = newMockProvider(embedResponse = @[0.1, 0.2, 0.3])
    let emb = waitFor safeGetEmbedding(provider, "hello")
    check emb.len == 3
    check emb[0] == 0.1

  test "safeGetEmbedding returns empty seq on failure":
    let provider = FailingEmbeddingProvider()
    let emb = waitFor safeGetEmbedding(provider, "hello")
    check emb.len == 0

# =============================================================================
# OpenAI Provider
# =============================================================================

suite "OpenAI Provider":
  test "newOpenAIProvider with defaults":
    let p = newOpenAIProvider("sk-test")
    check p.apiKey == "sk-test"
    check p.model == "gpt-3.5-turbo"
    check p.baseUrl == "https://api.openai.com/v1"

  test "newOpenAIProvider with custom model and baseUrl":
    let p = newOpenAIProvider("sk-test", model = "gpt-4o",
                               baseUrl = "https://custom.openai.com/v1")
    check p.model == "gpt-4o"
    check p.baseUrl == "https://custom.openai.com/v1"

  test "getMaxContextTokens for gpt-4o":
    let p = newOpenAIProvider("sk", model = "gpt-4o")
    let res = waitFor p.getMaxContextTokens()
    check res == 128000

  test "getMaxContextTokens for gpt-4":
    let p = newOpenAIProvider("sk", model = "gpt-4")
    let res = waitFor p.getMaxContextTokens()
    check res == 8192

  test "getMaxContextTokens for gpt-3.5-turbo":
    let p = newOpenAIProvider("sk", model = "gpt-3.5-turbo")
    let res = waitFor p.getMaxContextTokens()
    check res == 16384

  test "supportsVision for gpt-4o":
    let p = newOpenAIProvider("sk", model = "gpt-4o")
    check p.supportsVision() == true

  test "supportsVision for gpt-3.5-turbo":
    let p = newOpenAIProvider("sk", model = "gpt-3.5-turbo")
    check p.supportsVision() == false

  test "countTokens is inherited fallback":
    let p = newOpenAIProvider("sk")
    check p.countTokens("abcdefgh") == 2

# =============================================================================
# Ollama Provider
# =============================================================================

suite "Ollama Provider":
  test "newOllamaProvider defaults":
    let p = newOllamaProvider()
    check p.baseUrl == "http://localhost:11434"
    check p.model == "llama3"
    check p.temperature == 0.7
    check p.maxRetries == 3
    check p.apiKey == ""

  test "baseUrl strips trailing slash":
    let p = newOllamaProvider(baseUrl = "http://localhost:11434/")
    check p.baseUrl == "http://localhost:11434"

  test "maxRetries is initialized to 3":
    let p = newOllamaProvider()
    check p.maxRetries == 3

  test "supportsTools default true":
    let p = newOllamaProvider()
    check p.supportsTools() == true

  test "supportsVision default false":
    let p = newOllamaProvider()
    check p.supportsVision() == false

  test "countTokens is inherited fallback":
    let p = newOllamaProvider()
    check p.countTokens("abcdefgh") == 2

  test "getMaxContextTokens fallback is 8192":
    let p = newOllamaProvider()
    let res = waitFor p.getMaxContextTokens()
    check res == 8192
