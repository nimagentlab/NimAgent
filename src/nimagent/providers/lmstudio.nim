## LLM Provider for LM Studio
## LM Studio exposes a 100% OpenAI-compatible API (usually on port 1234)
import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import std/[strformat, strutils]

import ./base
import ../messages

type
  LMStudioProvider* = ref object of LLMProvider
    baseUrl*: string
    model*: string

proc newLMStudioProvider*(baseUrl: string = "http://localhost:1234/v1", model: string = "local-model"): LMStudioProvider =
  LMStudioProvider(baseUrl: baseUrl, model: model)

method generate*(provider: LMStudioProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let client = newHttpCompatClient()
  let headers = @[("Content-Type", "application/json")]

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

    if msg.role == Tool: msgJson["tool_call_id"] = %msg.toolCallId
    if msg.toolCalls.len > 0:
      var tcArray = newJArray()
      for tc in msg.toolCalls:
        tcArray.add(%*{"id": tc.id, "type": "function", "function": {"name": tc.name, "arguments": tc.arguments}})
      msgJson["tool_calls"] = tcArray
    apiMessages.add(msgJson)

  let body = %*{ "model": provider.model, "messages": apiMessages }
  if forceJson: body["response_format"] = %*{ "type": "json_object" }
  if not toolsSchema.isNil and toolsSchema.len > 0:
    body["tools"] = toolsSchema
    body["tool_choice"] = %"auto"

  try:
    let response = await client.post(provider.baseUrl & "/chat/completions", $body, headers)
    let responseBody = response.body
    if response.is2xx:
      let jsonResp = parseJson(responseBody)
      let replyMsg = jsonResp["choices"][0]["message"]
      var outMsg = Message(role: Assistant, content: "")
      if replyMsg.hasKey("content") and replyMsg["content"].kind != JNull:
        outMsg.content = replyMsg["content"].getStr()
      if replyMsg.hasKey("tool_calls"):
        for tc in replyMsg["tool_calls"]:
          outMsg.toolCalls.add(ToolCall(id: tc["id"].getStr(), name: tc["function"]["name"].getStr(), arguments: tc["function"]["arguments"].getStr()))
      return outMsg
    else: raise newException(ValueError, fmt"LMStudio Error: HTTP {response.code} - {responseBody}")
  finally: client.close()

method getEmbedding*(provider: LMStudioProvider, text: string): Future[seq[float]] {.async.} =
  let client = newHttpCompatClient()
  let headers = @[("Content-Type", "application/json")]
  let body = %*{ "model": provider.model, "input": text }
  try:
    let response = await client.post(provider.baseUrl & "/embeddings", $body, headers)
    let responseBody = response.body
    if response.is2xx:
      let jsonResp = parseJson(responseBody)
      var embedding: seq[float] = @[]
      for val in jsonResp["data"][0]["embedding"]: embedding.add(val.getFloat())
      return embedding
    else: raise newException(ValueError, fmt"LMStudio Embedding Error: HTTP {response.code} - {responseBody}")
  finally: client.close()
