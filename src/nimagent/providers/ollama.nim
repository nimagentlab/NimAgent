import ../utils/async_compat
import ../utils/json_compat
import ../utils/http_compat
import std/[strutils, net]
import ../messages
import ./base

type
  OllamaProvider* = ref object of LLMProvider
    baseUrl*: string
    model*: string
    apiKey*: string
    temperature*: float
    maxRetries*: int

proc newOllamaProvider*(baseUrl: string = "http://localhost:11434",
                        model: string = "llama3",
                        apiKey: string = "",
                        temperature: float = 0.7): OllamaProvider =
  OllamaProvider(
    baseUrl: baseUrl.strip(chars = {'/'}),
    model: model,
    apiKey: apiKey,
    temperature: temperature,
    maxRetries: 3
  )

method generate*(provider: OllamaProvider, messages: seq[Message],
                 toolsSchema: JsonNode = nil,
                 forceJson: bool = false): Future[Message] {.async.} =
  ## Generates a response via the Ollama/OpenAI-compatible API
  var headers = newJsonHeaders()
  if provider.apiKey != "":
    headers.add(("Authorization", "Bearer " & provider.apiKey))
  let client = newHttpCompatClient(headers)

  # Build messages array
  var msgsJson = newJArray()
  for msg in messages:
    var m = newJObject()
    m["role"] = %($msg.role).toLowerAscii()
    
    # Support Multimodal (Vision)
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
      m["content"] = contentArr
    else:
      m["content"] = %msg.content
    if msg.toolCallId != "":
      m["tool_call_id"] = %msg.toolCallId
    if msg.toolCalls.len > 0:
      var calls = newJArray()
      for tc in msg.toolCalls:
        calls.add(%*{
          "id": tc.id,
          "type": "function",
          "function": {"name": tc.name, "arguments": tc.arguments}
        })
      m["tool_calls"] = calls
    msgsJson.add(m)

  # Body
  var body = %*{
    "model": provider.model,
    "messages": msgsJson,
    "temperature": provider.temperature,
    "stream": false
  }

  if forceJson:
    body["response_format"] = %*{"type": "json_object"}

  if toolsSchema != nil and toolsSchema.kind == JArray and toolsSchema.len > 0:
    body["tools"] = toolsSchema

  # Send with retry
  var lastError = ""
  for attempt in 0..<provider.maxRetries:
    try:
      let url = provider.baseUrl & "/v1/chat/completions"
      let response = await client.post(url, $body, headers)
      let respJson = parseJson(response.body)

      if respJson.hasKey("error"):
        lastError = respJson["error"]["message"].getStr("Unknown error")
        continue

      let choice = respJson["choices"][0]
      let msgJson = choice["message"]

      var resultMsg = Message(
        role: Assistant,
        content: msgJson{"content"}.getStr("")
      )

      # Handle tool calls
      if msgJson.hasKey("tool_calls") and msgJson["tool_calls"].kind == JArray:
        for tc in msgJson["tool_calls"]:
          let toolCall = ToolCall(
            id: tc["id"].getStr(""),
            name: tc["function"]["name"].getStr(""),
            arguments: $tc["function"]["arguments"]
          )
          resultMsg.toolCalls.add(toolCall)

      return resultMsg

    except CatchableError as e:
      lastError = e.msg
      if attempt < provider.maxRetries - 1:
        await sleepAsync(1000 * (attempt + 1))
    finally:
      client.close()

  # All attempts failed
  return Message(role: Assistant, content: "[LLM Error after " &
      $provider.maxRetries & " attempts: " & lastError & "]")

method getEmbedding*(provider: OllamaProvider, text: string): Future[seq[
    float]] {.async.} =
  ## Gets an embedding via the API
  var headers = newJsonHeaders()
  if provider.apiKey != "":
    headers.add(("Authorization", "Bearer " & provider.apiKey))
  let client = newHttpCompatClient(headers)

  let body = %*{"model": provider.model, "input": text}
  let url = provider.baseUrl & "/v1/embeddings"

  try:
    let response = await client.post(url, $body, headers)
    let respJson = parseJson(response.body)

    result = @[]
    for v in respJson["data"][0]["embedding"]:
      result.add(v.getFloat())
  except:
    result = @[]
  finally:
    client.close()

# Constants for cloud access (to be moved to config)
method setBaseUrl*(provider: OllamaProvider, url: string) =
  provider.baseUrl = url.strip(chars = {'/'})

method setApiKey*(provider: OllamaProvider, key: string) =
  provider.apiKey = key

method setModel*(provider: OllamaProvider, model: string) =
  provider.model = model

const
  OLLAMA_CLOUD_URL* = "https://ollama.com/api"
  OLLAMA_CLOUD_KEY* = ""
