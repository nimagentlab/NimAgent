import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import ./base
import ../messages
import std/[strformat, strutils]

type
  OpenAIProvider* = ref object of LLMProvider
    apiKey*: string
    model*: string
    baseUrl*: string
    client: HttpCompatClient

proc newOpenAIProvider*(apiKey: string, model: string = "gpt-3.5-turbo",
  baseUrl: string = "https://api.openai.com/v1"): OpenAIProvider =
  return OpenAIProvider(
    apiKey: apiKey,
    model: model,
    baseUrl: baseUrl,
    client: newHttpCompatClient()
  )

method generate*(provider: OpenAIProvider, messages: seq[Message],
    toolsSchema: JsonNode = nil, forceJson: bool = false): Future[
    Message] {.async.} =
  let client = provider.client

  # Configuration des headers
  let headers = @[
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " & provider.apiKey)
  ]

  # Construction des messages pour l'API
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
        contentArr.add(%*{
          "type": "image_url",
          "image_url": {"url": imgUrl}
        })
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
    body["response_format"] = %*{"type": "json_object"}

  if not toolsSchema.isNil and toolsSchema.len > 0:
    body["tools"] = toolsSchema
    body["tool_choice"] = %"auto"

  let apiUrl = provider.baseUrl & "/chat/completions"

  try:
    let response = await client.post(apiUrl, $body, headers)
    let responseBody = response.body

    if response.is2xx:
      let jsonResp = parseJson(responseBody)
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
      raise newException(ValueError, fmt"API Error: HTTP {response.code} - {responseBody}")
  except Exception as e:
    raise e

method getEmbedding*(provider: OpenAIProvider, text: string): Future[seq[
    float]] {.async.} =
  let client = provider.client

  let headers = @[
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " & provider.apiKey)
  ]

  # Using OpenAI's high-performance, low-cost model for embeddings
  let body = %*{
    "model": "text-embedding-3-small",
    "input": text
  }

  let apiUrl = provider.baseUrl & "/embeddings"

  try:
    let response = await client.post(apiUrl, $body, headers)
    let responseBody = response.body

    if response.is2xx:
      let jsonResp = parseJson(responseBody)
      var embedding: seq[float] = @[]

      # Extracting the float array
      for val in jsonResp["data"][0]["embedding"]:
        embedding.add(val.getFloat())

      return embedding
    else:
      raise newException(ValueError, fmt"Embedding API Error: HTTP {response.code} - {responseBody}")
  except Exception as e:
    raise e

# =============================================================================
# Polymorphic Introspection for OpenAI
# =============================================================================

method isAlive*(provider: OpenAIProvider): Future[bool] {.async.} =
  let client = provider.client
  let headers = @[("Authorization", "Bearer " & provider.apiKey)]
  try:
    let response = await client.get(provider.baseUrl & "/models", headers)
    return response.is2xx
  except Exception:
    return false

method getAvailableModels*(provider: OpenAIProvider): Future[seq[
    string]] {.async.} =
  let client = provider.client
  let headers = @[("Authorization", "Bearer " & provider.apiKey)]
  try:
    let response = await client.get(provider.baseUrl & "/models", headers)
    if not response.is2xx: return @[]
    let respJson = parseJson(response.body)
    var models: seq[string] = @[]
    for m in respJson["data"]:
      models.add(m["id"].getStr())
    return models
  except Exception:
    return @[]

method getMaxContextTokens*(provider: OpenAIProvider): Future[int] {.async.} =
  # OpenAI models have static context limits mapped by name
  let m = provider.model
  if m.contains("gpt-4o") or m.contains("gpt-4-turbo"): return 128000
  if m.contains("gpt-4"): return 8192
  if m.contains("gpt-3.5-turbo-16k"): return 16384
  if m.contains("gpt-3.5-turbo"): return 16384 # 0125 versions
  return 8192

method supportsVision*(provider: OpenAIProvider): bool =
  return provider.model.contains("gpt-4o") or provider.model.contains("vision")

method setBaseUrl*(provider: OpenAIProvider, url: string) =
  provider.baseUrl = url

method setApiKey*(provider: OpenAIProvider, key: string) =
  provider.apiKey = key

method setModel*(provider: OpenAIProvider, model: string) =
  provider.model = model
