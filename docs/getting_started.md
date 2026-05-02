# Getting started with nimagent

## Prerequisites

- Nim 2.0.0 or newer.
- Either an API key for a hosted provider or a local model server such as Ollama, LM Studio, or llama.cpp.

## Installation

```bash
nimble install nimagent
```

## First agent

Create `hello.nim`:

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

  let response = await agent.run("Hello! Who are you?")
  echo response

waitFor main()
```

Set the API key:

```bash
export OPENAI_API_KEY="<your-openai-api-key>"
```

Compile and run:

```bash
nim c -r hello.nim
```

Release build:

```bash
nim c -d:release hello.nim
./hello
```

## Local provider example

With Ollama running locally:

```nim
import nimagent/providers/ollama

let provider = newOllamaProvider(
  baseUrl = "http://localhost:11434",
  model = "llama3.2"
)
```

## Configuration helpers

`getApiKey("openai")` reads `OPENAI_API_KEY`.

`getApiKey("anthropic")` reads `ANTHROPIC_API_KEY`.

`getApiKey("gemini")` reads `GEMINI_API_KEY`.

`getOllamaHost()` reads `OLLAMA_HOST`, with `http://localhost:11434` as the default.

## Next steps

- [Create an agent with tools](tools.md)
- [Configure providers](provider_setup.md)
- [Compile an agent](compiled_agents.md)
- [Use runtime hooks](runtime_hooks.md)
