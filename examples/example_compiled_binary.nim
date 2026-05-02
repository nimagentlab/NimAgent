## Example 4: Agent compiled into standalone binary
## Compile with: nim c -d:release 04_compiled_agent_binary.nim
## Run: ./04_compiled_agent_binary
##
## This example shows how to create a compiled agent that requires
## no runtime dependencies (except network connection for the LLM API).

import std/[asyncdispatch, os]
import nimagent
import nimagent/providers/ollama

proc main() {.async.} =
  # Get command line arguments
  let args = commandLineParams()
  let prompt = if args.len > 0: args[0] else: "Say hello"

  echo "=== Standalone compiled agent ==="
  echo "Prompt: ", prompt
  echo ""

  # Configuration with Ollama (local model)
  let provider = newOllamaProvider(
    baseUrl = "http://localhost:11434",
    model = "llama3.2"
  )

  # Minimal agent creation
  let agent = newAgent(
    name = "CompiledAgent",
    provider = provider,
    config = AgentConfig(
      maxSteps: 5,
      enableTracing: false  # Disabled for production
    )
  )

  # Execution
  let response = await agent.run(prompt)
  echo response

when isMainModule:
  waitFor main()
