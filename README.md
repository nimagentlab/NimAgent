# nimagent

A lightweight Nim SDK for building small, inspectable AI agents that compile to native binaries.

## Key features

- **Native binaries**: compile agents to standalone executables with zero runtime dependencies.
- **Simple ReAct loop**: run an agent with a provider, memory, and optional tools.
- **Multiple providers**: OpenAI-compatible APIs, Anthropic, Ollama, LM Studio, llama.cpp, and Gemini.
- **Tool registry**: define and register JSON-schema tools in Nim via the `llmTool` macro.
- **Runtime hooks**: instrument inference, tool calls, and errors.
- **Security layer**: configurable security levels with path traversal detection, command injection prevention, and human-in-the-loop validation.
- **Skills manager**: load domain-specific skills from a directory and inject them into the agent context.
- **Computer control**: OS automation tools (screenshot, mouse, keyboard, window focus, OCR) via standard system binaries.
- **JSON Schema validation**: validate tool arguments against JSON Schema subsets.
- **Runtime provider switching**: change model or provider at runtime when compiled with `cfgProvider` enabled.
- **No Python/Node runtime required** for compiled agents.

## Status

`nimagent` is an early public SDK. The API is usable for experiments and small local-first agents, but it may change before `v1.0`.

## Installation

```bash
nimble install nimagent
```

Or add it to your `.nimble` file:

```nim
requires "nimagent >= 0.1.0"
```

## Quick start

```nim
import std/asyncdispatch
import nimagent
import nimagent/providers/openai_compatible

proc main() {.async.} =
  let provider = newOpenAIProvider(
    apiKey = getApiKey("openai"),
    model = "gpt-4o-mini"
  )

  let agent = newAgent(
    name = "Assistant",
    provider = provider
  )

  let response = await agent.run("Hello!")
  echo response

waitFor main()
```

Set your API key first:

```bash
export OPENAI_API_KEY="<your-openai-api-key>"
```

## Agent with tools

```nim
import std/asyncdispatch
import nimagent

llmTool "Adds two numbers":
  proc add(a, b: int): Future[int] {.async.} =
    return a + b

let tools = newToolRegistry()
tools.register(addTool())
```

See [`examples/example_tool_calling.nim`](examples/example_tool_calling.nim) for a complete example.

## Security

`nimagent` provides four security levels that can be set at compile time or runtime:

| Level | Behavior |
|-------|----------|
| `secNone` | No validation. Use only in sandboxed environments. |
| `secStandard` | Technical validation (path traversal, command injection) + HITL on dangerous actions. |
| `secCognitif` | LLM reflection before action + HITL on dangerous actions. |
| `secAlways` | Human confirmation required for **all** actions. |

Enable at compile time:

```nim
let agent = newAgent("SecureBot", provider)
agent.securityLevel = secStandard
```

Or allow runtime reconfiguration:

```nim
agent.allowedRuntimeConfigs = {cfgSecurity, cfgModel, cfgProvider}
# Later: JSON runtime config can update security, model, and provider
```

## Local models

`nimagent` can target local model servers through providers such as Ollama, LM Studio, and llama.cpp.

Example with Ollama:

```nim
import nimagent/providers/ollama

let provider = newOllamaProvider(
  baseUrl = "http://localhost:11434",
  model = "llama3.2"
)
```

Example with llama.cpp server:

```nim
import nimagent/providers/llamacpp

let provider = newLlamaCppProvider(
  baseUrl = "http://localhost:8080",
  model = "local-model"
)
```

## Computer control (optional)

Agents can interact with the desktop environment when `computer_control` tools are registered:

```nim
import nimagent/tools/builtin/computer_control

let tools = newToolRegistry()
tools.register(take_screenshotTool())
tools.register(mouse_clickTool())
tools.register(keyboard_typeTool())
```

Requires `xdotool`, `scrot`, and `tesseract` on the host system.

## Documentation

- [Getting Started](docs/getting_started.md)
- [Compiled Agents](docs/compiled_agents.md)
- [Provider Configuration](docs/provider_setup.md)
- [Tools](docs/tools.md)
- [Runtime Hooks](docs/runtime_hooks.md)

## Architecture

```text
Your code
  ↓
Agent → Provider → Tools → Memory
  ↓
Runtime hooks, tracing, security, async compatibility
```

## Tests

```bash
nimble test
nimble examples
```

## Roadmap

See [ROADMAP.md](ROADMAP.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
