# nimagent roadmap

## v0.1.0 — Initial public SDK

Delivered:

- Minimal SDK structure.
- Provider support for OpenAI-compatible APIs, Anthropic, Ollama, LM Studio, llama.cpp, and Gemini.
- Tool registry and `llmTool` macro.
- Basic conversation memory.
- Runtime hooks for inference, tool calls, and errors.
- Async compatibility layer.
- Examples and basic unit tests.

## v0.2.x — Stabilization

Planned candidates:

- More complete example coverage.
- Clearer provider error handling.
- Streaming support where providers expose it.
- Basic vector memory as an optional module.
- Safer workspace/file tools.
- CLI scaffolding for small projects.

## v0.3.x — Local-first runtime work

Potential candidates:

- Better llama.cpp and Ollama ergonomics.
- Optional process runner for local model servers.
- Preconfigured agent templates.
- Structured tracing output.
- Small observability hooks.

## Later

Possible future packages may be kept separate from the initial SDK until they are stable. The initial public repository should remain small and easy to audit.

Dates are intentionally not promised. The priority is a small, reliable public SDK.
