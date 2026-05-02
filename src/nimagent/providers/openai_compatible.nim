import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import ./base
import ../messages
import std/strformat

type
  OpenAIProvider* = ref object of LLMProvider
    apiKey*: string
    model*: string

proc newOpenAIProvider*(apiKey: string, model: string = "gpt-3.5-turbo"): OpenAIProvider =
  OpenAIProvider(apiKey: apiKey, model: model)

method generate*(provider: OpenAIProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let client = newHttpCompatClient()

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

    var msgJson = %*{
      "role": roleStr,
      "content": if msg.content.len > 0: %msg.content else: newJNull()
    }

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

  if not toolsSchema.isNil and toolsSchema.len > 0:
    body["tools"] = toolsSchema
    body["tool_choice"] = %"auto"

  let apiUrl = "https://api.openai.com/v1/chat/completions"

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
  finally:
    client.close()

method getEmbedding*(provider: OpenAIProvider, text: string): Future[seq[float]] {.async.} =
  let client = newHttpCompatClient()

  let headers = @[
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer " & provider.apiKey)
  ]

  # Using OpenAI's high-performance, low-cost model for embeddings
  let body = %*{
    "model": "text-embedding-3-small",
    "input": text
  }

  let apiUrl = "https://api.openai.com/v1/embeddings"

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
  finally:
    client.close()
