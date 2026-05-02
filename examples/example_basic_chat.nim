## Example 1: Basic chat agent
## Compile with: nim c -d:release 01_basic_chat_agent.nim

import std/asyncdispatch
import nimagent
import nimagent/providers/openai_compatible

proc main() {.async.} =
  echo "=== Basic chat agent ==="

  # OpenAI provider configuration
  let provider = newOpenAIProvider(
    apiKey = getApiKey("openai"),
    model = "gpt-4o-mini"
  )

  # Agent creation
  let agent = newAgent(
    name = "ChatBot",
    provider = provider,
    config = AgentConfig(
      maxSteps: 10,
      maxContextChars: 60000,
      enableTracing: true
    )
  )

  # Execution
  let response = await agent.run("Hello! Who are you?")
  echo "\nResponse:", response

when isMainModule:
  waitFor main()
