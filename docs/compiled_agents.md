# Compiled agents

A practical advantage of `nimagent` is that an agent can be compiled into a native executable.

## Why compile?

- Simple distribution: one binary instead of a Python or Node project tree.
- Local-first deployment: useful for CLI tools, local assistants, and edge-like environments.
- Predictable runtime surface: the application starts from a compiled entry point.
- Easy operational packaging: Docker images or release artifacts can be small.

A compiled agent may still need network access or a local model server, depending on the provider you choose.

## Minimal example

```nim
import std/asyncdispatch
import nimagent
import nimagent/providers/ollama

proc main() {.async.} =
  let provider = newOllamaProvider(
    baseUrl = "http://localhost:11434",
    model = "llama3.2"
  )

  let agent = newAgent(
    name = "CompiledAgent",
    provider = provider
  )

  let response = await agent.run("Explain compilation in Nim.")
  echo response

waitFor main()
```

## Compilation

Development:

```bash
nim c -r agent.nim
```

Release build:

```bash
nim c -d:release agent.nim
```

Size-oriented build:

```bash
nim c -d:release --opt:size agent.nim
```

Cross-compilation depends on the target compiler/toolchain being installed and configured:

```bash
nim c -d:release --os:windows --cpu:amd64 agent.nim
nim c -d:release --os:linux --cpu:amd64 agent.nim
```

## Tools in compiled agents

Tools are normal Nim code compiled with the agent:

```nim
import std/asyncdispatch
import nimagent

llmTool "Adds two integers":
  proc add(a, b: int): Future[int] {.async.} =
    return a + b

let tools = newToolRegistry()
tools.register(addTool())
```

For file access, prefer the built-in workspace tools rather than ad-hoc filesystem tools. Workspace tools are restricted to a workspace root and apply path and size checks.

## Basic runtime practices

- Keep `maxSteps` low for small CLI agents.
- Disable tracing for quiet release builds if you do not need logs.
- Prefer local providers for sensitive data.
- Treat every tool as part of the trusted computing base.

```nim
let agent = newAgent(
  name = "SmallAgent",
  provider = provider,
  config = AgentConfig(
    maxSteps: 10,
    maxContextChars: 60000,
    enableTracing: false
  )
)
```

## Docker sketch

```dockerfile
FROM nimlang/nim:latest AS builder
WORKDIR /app
COPY . .
RUN nimble install -y --depsOnly
RUN nim c -d:release agent.nim

FROM debian:stable-slim
COPY --from=builder /app/agent /usr/local/bin/agent
ENTRYPOINT ["/usr/local/bin/agent"]
```
