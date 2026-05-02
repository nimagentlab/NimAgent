# Provider configuration

`nimagent` exposes provider objects that implement a common `LLMProvider` interface.

## OpenAI-compatible APIs

```nim
import nimagent/providers/openai_compatible

let provider = newOpenAIProvider(
  apiKey = getApiKey("openai"),
  model = "gpt-4o-mini"
)
```

The current OpenAI-compatible provider targets the OpenAI API endpoint directly. Additional OpenAI-compatible base URLs may be added later as a separate constructor or provider.

## Anthropic

```nim
import nimagent/providers/anthropic

let provider = newAnthropicProvider(
  apiKey = getApiKey("anthropic"),
  model = "claude-3-haiku-20240307"
)
```

## Ollama

Start a local Ollama server and make sure the chosen model is available.

```bash
ollama run llama3.2
```

```nim
import nimagent/providers/ollama

let provider = newOllamaProvider(
  baseUrl = "http://localhost:11434",
  model = "llama3.2"
)
```

## LM Studio

Enable the local server in LM Studio, then configure the provider:

```nim
import nimagent/providers/lmstudio

let provider = newLMStudioProvider(
  baseUrl = "http://localhost:1234/v1",
  model = "local-model"
)
```

## llama.cpp

Run `llama-server` with an OpenAI-compatible endpoint, then configure:

```nim
import nimagent/providers/llamacpp

let provider = newLlamaCppProvider(
  baseUrl = "http://localhost:8080",
  model = "local-model"
)
```

## Google Gemini

```nim
import nimagent/providers/gemini

let provider = newGeminiProvider(
  apiKey = getApiKey("gemini"),
  model = "gemini-1.5-flash"
)
```

## Choosing a provider

For early development, local providers such as Ollama or LM Studio are convenient because they avoid network API costs.

For higher-quality hosted inference, use a hosted provider and keep keys in environment variables. Do not commit keys, `.env` files, or local configuration files.

For edge-like or offline experiments, llama.cpp is the most direct target.
