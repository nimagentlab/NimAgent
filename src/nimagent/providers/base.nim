import ../utils/async_compat
import ../utils/json_compat
import ../messages

type
  LLMProvider* = ref object of RootObj
    
method generate*(provider: LLMProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.base, async.} =
  ## Base method to be implemented by each provider (OpenAI, Anthropic, etc.)
  quit "To be implemented"

method getEmbedding*(provider: LLMProvider, text: string): Future[seq[float]] {.base, async.} =
  ## Transforms text into a mathematical vector (Embedding) for semantic search.
  quit "To be implemented"
