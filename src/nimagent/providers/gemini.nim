## LLM Provider for Google Gemini (native API)
import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import std/[strformat, strutils]
import ./base
import ../messages

type
  GeminiProvider* = ref object of LLMProvider
    apiKey*: string
    model*: string

proc newGeminiProvider*(apiKey: string, model: string = "gemini-1.5-flash-latest"): GeminiProvider =
  GeminiProvider(apiKey: apiKey, model: model)

method generate*(provider: GeminiProvider, messages: seq[Message], toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let client = newHttpCompatClient(@[("Content-Type", "application/json")])
  
  var contents = newJArray()
  var systemInstruction: JsonNode = nil
  
  for msg in messages:
    if msg.role == System:
      systemInstruction = %*{"role": "user", "parts": [{"text": msg.content}]}
    elif msg.role == User:
      var parts = newJArray()
      parts.add(%*{"text": msg.content})
      for img in msg.images:
        var mimeType = "image/jpeg"
        var b64 = img
        if img.startsWith("data:"):
          let sParts = img.split(";")
          if sParts.len >= 2:
            mimeType = sParts[0].replace("data:", "")
            b64 = sParts[1].replace("base64,", "")
        parts.add(%*{"inlineData": {"mimeType": mimeType, "data": b64}})
      contents.add(%*{"role": "user", "parts": parts})
    elif msg.role == Assistant:
      var parts = newJArray()
      if msg.content.len > 0:
        parts.add(%*{"text": msg.content})
      for tc in msg.toolCalls:
        parts.add(%*{"functionCall": {"name": tc.name, "args": parseJson(tc.arguments)}})
      contents.add(%*{"role": "model", "parts": parts})
    elif msg.role == Tool:
      # Gemini API expects tool results to be sent by the user
      contents.add(%*{"role": "user", "parts": [{"functionResponse": {"name": "tool", "response": {"content": msg.content}}}]})

  let body = %*{ "contents": contents }
  if systemInstruction != nil: body["systemInstruction"] = systemInstruction
  if forceJson: body["generationConfig"] = %*{"responseMimeType": "application/json"}
  
  # Tool conversion
  if not toolsSchema.isNil and toolsSchema.len > 0:
    var funcDecls = newJArray()
    for t in toolsSchema:
      # Gemini uses uppercase types for its native schema but accepts basic JSON schema
      funcDecls.add(%*{
        "name": t["function"]["name"],
        "description": t["function"]["description"],
        "parameters": t["function"]["parameters"]
      })
    body["tools"] = %*{"functionDeclarations": funcDecls}

  let apiUrl = fmt"https://generativelanguage.googleapis.com/v1beta/models/{provider.model}:generateContent?key={provider.apiKey}"

  try:
    let response = await client.post(apiUrl, $body, newJsonHeaders())
    if response.is2xx:
      let jsonResp = parseJson(response.body)
      var outMsg = Message(role: Assistant, content: "")
      
      if jsonResp.hasKey("candidates") and jsonResp["candidates"].len > 0:
        let parts = jsonResp["candidates"][0]["content"]["parts"]
        for p in parts:
          if p.hasKey("text"): outMsg.content &= p["text"].getStr()
          if p.hasKey("functionCall"):
            outMsg.toolCalls.add(ToolCall(
              id: "gemini_" & p["functionCall"]["name"].getStr(), # Gemini doesn't provide an ID, we simulate it
              name: p["functionCall"]["name"].getStr(),
              arguments: $p["functionCall"]["args"]
            ))
      return outMsg
    else: raise newException(ValueError, fmt"Gemini Error: HTTP {response.code} - {response.body}")
  finally: client.close()

method getEmbedding*(provider: GeminiProvider, text: string): Future[seq[float]] {.async.} =
  let client = newHttpCompatClient(@[("Content-Type", "application/json")])
  let body = %*{ "model": "models/text-embedding-004", "content": {"parts": [{"text": text}]} }
  let apiUrl = fmt"https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent?key={provider.apiKey}"

  try:
    let response = await client.post(apiUrl, $body, newJsonHeaders())
    if response.is2xx:
      let jsonResp = parseJson(response.body)
      var embedding: seq[float] = @[]
      for val in jsonResp["embedding"]["values"]: embedding.add(val.getFloat())
      return embedding
    else: raise newException(ValueError, fmt"Gemini Embedding API Error: HTTP {response.code} - {response.body}")
  finally: client.close()
