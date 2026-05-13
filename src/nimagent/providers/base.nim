import ../utils/async_compat
import ../utils/json_compat
import ../messages

type
  LLMProvider* = ref object of RootObj
    
method generate*(provider: LLMProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.base, async.} =
  ## Base method to be implemented by each provider (OpenAI, Anthropic, etc.)
  raise newException(CatchableError, "To be implemented")

method getEmbedding*(provider: LLMProvider, text: string): Future[seq[float]] {.base, async.} =
  ## Transforms text into a mathematical vector (Embedding) for semantic search.
  raise newException(CatchableError, "To be implemented")

proc safeGetEmbedding*(provider: LLMProvider, text: string): Future[seq[float]] {.async.} =
  ## Safe wrapper around getEmbedding. Returns empty vector on failure instead of crashing.
  try:
    return await provider.getEmbedding(text)
  except Exception:
    return @[]

method countTokens*(provider: LLMProvider, text: string): int {.base.} =
  ## Fast heuristic for token counting. 
  ## Derived providers can override this if they have a local tokenizer (like Tiktoken).
  return text.len div 4

method getMaxContextTokens*(provider: LLMProvider): Future[int] {.base, async.} =
  ## Returns the maximum context window size for the active model.
  ## Default fallback is 8192 if the provider cannot be queried dynamically.
  return 8192

# =============================================================================
# Capabilities Introspection (Polymorphism)
# =============================================================================

method supportsTools*(provider: LLMProvider): bool {.base.} =
  ## Does this provider/model natively support the Tool Calling API?
  ## If false, the agent can gracefully fallback to injecting tools into the system prompt.
  return true

method supportsVision*(provider: LLMProvider): bool {.base.} =
  ## Does this provider/model support multimodal vision (images in messages)?
  return false

method isAlive*(provider: LLMProvider): Future[bool] {.base, async.} =
  ## Ping the provider to check if it's reachable and authenticated.
  return true

method getAvailableModels*(provider: LLMProvider): Future[seq[string]] {.base, async.} =
  ## Fetch a list of all models available to this provider.
  return @[]
# =============================================================================
# Runtime Configuration (Provider Switching)
# =============================================================================

method setBaseUrl*(provider: LLMProvider, url: string) {.base.} =
  ## Updates the provider base URL at runtime.
  ## No-op by default - override in concrete providers.
  discard

method setApiKey*(provider: LLMProvider, key: string) {.base.} =
  ## Updates the provider API key at runtime.
  ## No-op by default - override in concrete providers.
  discard

method setModel*(provider: LLMProvider, model: string) {.base.} =
  ## Updates the provider model at runtime.
  ## No-op by default - override in concrete providers.
  discard

# =============================================================================
# Streaming
# =============================================================================

type StreamCallback* = proc(chunk: string): Future[void] {.closure, gcsafe.}

method generateStream*(
  provider: LLMProvider, 
  messages: seq[Message], 
  onChunk: StreamCallback, 
  toolsSchema: JsonNode = nil
): Future[Message] {.base, async.} =
  ## Streaming version of generate. 
  ## Yields tokens via the onChunk callback for real-time UI, then returns the final message.
  raise newException(CatchableError, "Streaming not implemented for this provider.")
