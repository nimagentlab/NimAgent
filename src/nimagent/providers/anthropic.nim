## LLM Provider for Anthropic (Claude 3)
## Note: Anthropic does not have a native Embedding API.
import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import std/[strformat]
import ./base
import ../messages

type
  AnthropicProvider* = ref object of LLMProvider
    apiKey*: string
    model*: string

proc newAnthropicProvider*(apiKey: string, model: string = "claude-3-haiku-20240307"): AnthropicProvider =
  AnthropicProvider(apiKey: apiKey, model: model)

method generate*(provider: AnthropicProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let client = newHttpCompatClient(@[
    ("x-api-key", provider.apiKey),
    ("anthropic-version", "2023-06-01"),
    ("content-type", "application/json")
  ])
  
  var apiMessages = newJArray()
  var systemPrompt = ""
  
  for msg in messages:
    if msg.role == System:
      systemPrompt &= msg.content & "\n"
    elif msg.role == User:
      apiMessages.add(%*{"role": "user", "content": msg.content})
    elif msg.role == Assistant:
      if msg.toolCalls.len > 0:
        var toolUses = newJArray()
        for tc in msg.toolCalls:
          toolUses.add(%*{"type": "tool_use", "id": tc.id, "name": tc.name, "input": parseJson(tc.arguments)})
        apiMessages.add(%*{"role": "assistant", "content": toolUses})
      else:
        apiMessages.add(%*{"role": "assistant", "content": msg.content})
    elif msg.role == Tool:
      apiMessages.add(%*{"role": "user", "content": [%*{"type": "tool_result", "tool_use_id": msg.toolCallId, "content": msg.content}]})

  let body = %*{
    "model": provider.model,
    "max_tokens": 4096,
    "messages": apiMessages
  }
  
  if systemPrompt.len > 0:
    body["system"] = %systemPrompt
    
  # Converting OAI schema to Anthropic format
  if not toolsSchema.isNil and toolsSchema.len > 0:
    var anthropicTools = newJArray()
    for t in toolsSchema:
      anthropicTools.add(%*{
        "name": t["function"]["name"],
        "description": t["function"]["description"],
        "input_schema": t["function"]["parameters"]
      })
    body["tools"] = anthropicTools

  try:
    let response = await client.post("https://api.anthropic.com/v1/messages", $body, newJsonHeaders())
    if response.is2xx:
      let jsonResp = parseJson(response.body)
      var outMsg = Message(role: Assistant, content: "")

      for blockNode in jsonResp["content"]:
        if blockNode["type"].getStr() == "text":
          outMsg.content &= blockNode["text"].getStr()
        elif blockNode["type"].getStr() == "tool_use":
          outMsg.toolCalls.add(ToolCall(
            id: blockNode["id"].getStr(),
            name: blockNode["name"].getStr(),
            arguments: $blockNode["input"]
          ))
      return outMsg
    else: raise newException(ValueError, fmt"Anthropic Error: HTTP {response.code} - {response.body}")
  finally: client.close()

method getEmbedding*(provider: AnthropicProvider, text: string): Future[seq[float]] {.async.} =
  raise newException(ValueError, "Anthropic does not offer a public embedding model. Use OpenAI or LlamaCpp for RAG vectors.")
