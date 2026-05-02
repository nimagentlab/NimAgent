## Configuration for nimagent

import std/[os, strutils]

proc getApiKey*(provider: string = "openai"): string =
  ## Retrieves the API key from environment variables
  ## or a simple configuration file.
  ##
  ## Supported environment variables:
  ## - OPENAI_API_KEY
  ## - ANTHROPIC_API_KEY
  ## - OLLAMA_HOST (for ollama, no key needed)

  let envVar = case provider.toLowerAscii()
    of "openai": "OPENAI_API_KEY"
    of "anthropic": "ANTHROPIC_API_KEY"
    of "gemini": "GEMINI_API_KEY"
    else: provider.toUpperAscii() & "_API_KEY"

  result = getEnv(envVar)
  if result.len == 0:
    raise newException(ValueError,
      "API key not found. Set the environment variable " & envVar)

proc getOllamaHost*(): string =
  ## Retrieves the Ollama host (default: http://localhost:11434)
  result = getEnv("OLLAMA_HOST", "http://localhost:11434")
