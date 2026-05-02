## Example 2: Agent with Ollama (local model)
## Compile with: nim c -d:release 02_ollama_agent.nim
## Requires: ollama run llama3.2

import std/asyncdispatch
import nimagent
import nimagent/providers/ollama

proc main() {.async.} =
  echo "=== Local Ollama Agent ==="

  # Ollama provider (no API key needed)
  let provider = newOllamaProvider(
    baseUrl = getOllamaHost(),
    model = "llama3.2",
    temperature = 0.7
  )

  # Agent creation
  let agent = newAgent(
    name = "LocalBot",
    provider = provider
  )

  # Execution
  let response = await agent.run("Explain the advantages of compiled LLM agents to me")
  echo "\nResponse:", response

when isMainModule:
  waitFor main()
