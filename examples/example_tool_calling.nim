## Example 3: Agent with tool calling
## Compile with: nim c -d:release 03_tool_calling_agent.nim

import std/[asyncdispatch, json, strutils]
import nimagent
import nimagent/providers/openai_compatible

## Manual tool definitions

proc add(a, b: int): string =
  return $(a + b)

proc addTool(): Tool =
  let schema = %*{
    "type": "object",
    "properties": {
      "a": {"type": "integer"},
      "b": {"type": "integer"}
    },
    "required": @["a", "b"]
  }
  proc action(args: JsonNode): Future[string] {.async.} =
    return add(args["a"].getInt(), args["b"].getInt())
  return Tool(name: "add", description: "Calculates the sum of two numbers", schema: schema, action: action)

proc getWeather(city: string): string =
  ## Simulates a weather API
  if city.toLowerAscii() == "paris":
    return "Sunny, 22°C"
  elif city.toLowerAscii() == "london":
    return "Cloudy, 15°C"
  else:
    return "Weather data unavailable for " & city

proc getWeatherTool(): Tool =
  let schema = %*{
    "type": "object",
    "properties": {
      "city": {"type": "string"}
    },
    "required": @["city"]
  }
  proc action(args: JsonNode): Future[string] {.async.} =
    return getWeather(args["city"].getStr())
  return Tool(name: "getWeather", description: "Gets the weather for a city", schema: schema, action: action)

proc main() {.async.} =
  echo "=== Agent with tools ==="

  # Tool registry creation
  let tools = newToolRegistry()
  tools.register(addTool())
  tools.register(getWeatherTool())

  # Provider configuration
  let provider = newOpenAIProvider(
    apiKey = getApiKey("openai"),
    model = "gpt-4o"
  )

  # Agent creation with tools
  let agent = newAgent(
    name = "ToolAgent",
    provider = provider,
    tools = tools
  )

  # Execution with a request that should use the tools
  let response = await agent.run(
    "What's the weather in Paris? Then calculate 15 + 27."
  )
  echo "\nFinal response:\n", response

when isMainModule:
  waitFor main()
