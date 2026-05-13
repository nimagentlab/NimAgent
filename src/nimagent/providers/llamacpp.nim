## Integration module for llama.cpp
## Enables agents to run 100% offline and locally
## using llama.cpp's native OpenAI-compatible server
import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import std/[strformat, strutils]
import ./base
import ../messages

type
  LlamaCppProvider* = ref object of LLMProvider
    baseUrl*: string
    model*: string

proc newLlamaCppProvider*(baseUrl: string = "http://localhost:8080", model: string = "local-model"): LlamaCppProvider =
  ## Initializes the LLM provider for a local llama.cpp server
  ## By default, llama-server runs on port 8080.
  LlamaCppProvider(baseUrl: baseUrl, model: model)

method generate*(provider: LlamaCppProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let client = newHttpCompatClient(newJsonHeaders())
  defer: client.close()

  # Building messages (llama-server follows OpenAI API)
  var apiMessages = newJArray()
  for msg in messages:
    let roleStr = case msg.role:
      of System: "system"
      of User: "user"
      of Assistant: "assistant"
      of Tool: "tool"
      
    var msgJson = newJObject()
    msgJson["role"] = %roleStr
    if msg.images.len > 0:
      var contentArr = newJArray()
      contentArr.add(%*{"type": "text", "text": msg.content})
      for img in msg.images:
        let imgUrl = if img.startsWith("http") or img.startsWith("data:image"): img 
                     else: "data:image/jpeg;base64," & img
        contentArr.add(%*{"type": "image_url", "image_url": {"url": imgUrl}})
      msgJson["content"] = contentArr
    else:
      msgJson["content"] = if msg.content.len > 0: %msg.content else: newJNull()
    
    if msg.role == Tool:
      msgJson["tool_call_id"] = %msg.toolCallId
      
    if msg.toolCalls.len > 0:
      var tcArray = newJArray()
      for tc in msg.toolCalls:
        tcArray.add(%*{
          "id": tc.id,
          "type": "function",
          "function": {
            "name": tc.name,
            "arguments": tc.arguments
          }
        })
      msgJson["tool_calls"] = tcArray
      
    apiMessages.add(msgJson)
  
  let body = %*{
    "model": provider.model,
    "messages": apiMessages
  }
  
  if forceJson:
    body["response_format"] = %*{ "type": "json_object" }
  
  # If tools are provided and the local model supports them
  if not toolsSchema.isNil and toolsSchema.len > 0:
    body["tools"] = toolsSchema
    body["tool_choice"] = %"auto"
  
  let apiUrl = provider.baseUrl & "/v1/chat/completions"
  
  try:
    let response = await client.post(apiUrl, $body, newJsonHeaders())

    if response.is2xx:
      let jsonResp = parseJson(response.body)
      let replyMsg = jsonResp["choices"][0]["message"]

      var outMsg = Message(role: Assistant, content: "")
      if replyMsg.hasKey("content") and replyMsg["content"].kind != JNull:
        outMsg.content = replyMsg["content"].getStr()

      if replyMsg.hasKey("tool_calls"):
        for tc in replyMsg["tool_calls"]:
          outMsg.toolCalls.add(ToolCall(
            id: tc["id"].getStr(),
            name: tc["function"]["name"].getStr(),
            arguments: tc["function"]["arguments"].getStr()
          ))

      return outMsg
    else:
      raise newException(ValueError, fmt"Llama.cpp server error: HTTP {response.code} - {response.body}")
  except Exception as e:
    raise e

method getEmbedding*(provider: LlamaCppProvider, text: string): Future[seq[float]] {.async.} =
  let client = newHttpCompatClient(newJsonHeaders())
  defer: client.close()

  let body = %*{
    "model": provider.model,
    "input": text
  }

  # Compatible endpoint for vector creation
  let apiUrl = provider.baseUrl & "/v1/embeddings"

  try:
    let response = await client.post(apiUrl, $body, newJsonHeaders())

    if response.is2xx:
      let jsonResp = parseJson(response.body)
      var embedding: seq[float] = @[]

      for val in jsonResp["data"][0]["embedding"]:
        embedding.add(val.getFloat())

      return embedding
    else:
      raise newException(ValueError, fmt"Llama.cpp Embedding API Error: HTTP {response.code} - {response.body}")
  except Exception as e:
    raise e

# =============================================================================
# Polymorphic Introspection for Llama.cpp
# =============================================================================

method isAlive*(provider: LlamaCppProvider): Future[bool] {.async.} =
  let client = newHttpCompatClient()
  defer: client.close()
  try:
    let response = await client.get(provider.baseUrl & "/health")
    return response.is2xx
  except Exception:
    return false

method getAvailableModels*(provider: LlamaCppProvider): Future[seq[string]] {.async.} =
  let client = newHttpCompatClient()
  defer: client.close()
  try:
    let response = await client.get(provider.baseUrl & "/v1/models")
    if not response.is2xx: return @[]
    let respJson = parseJson(response.body)
    var models: seq[string] = @[]
    for m in respJson["data"]:
      models.add(m["id"].getStr())
    return models
  except Exception:
    return @[]

method getMaxContextTokens*(provider: LlamaCppProvider): Future[int] {.async.} =
  let client = newHttpCompatClient()
  defer: client.close()
  try:
    # Llama.cpp exposes configuration at /props
    let response = await client.get(provider.baseUrl & "/props")
    if not response.is2xx: return 8192
    let respJson = parseJson(response.body)
    if respJson.hasKey("default_generation_settings") and respJson["default_generation_settings"].hasKey("n_ctx"):
      return respJson["default_generation_settings"]["n_ctx"].getInt()
    return 8192
  except Exception:
    return 8192

method supportsVision*(provider: LlamaCppProvider): bool =
  # Llama.cpp requires a specific mmproj file to support vision, 
  # returning false safely by default unless explicitly configured.
  return false
