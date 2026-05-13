## nimagent - Configuration
## API key management and provider configuration.
# NOTE: Build flags like switch("os", "windows") must go in a config.nims file,
# not in a standard .nim module.

import std/[os, strutils, json, options]
import ./core/security

type
  RuntimeConfig* = object
    securityLevel*: Option[SecurityLevel]
    model*: string
    baseUrl*: string
    apiKey*: string
    enableVision*: Option[bool]

proc loadRuntimeConfig*(configPath: string = "", useEnv: bool = true): JsonNode =
  ## Creates a dynamic configuration object.
  ## The binary uses NO file by default (Design Choice).
  result = newJObject()
  
  if configPath != "" and fileExists(configPath):
    try:
      result = parseFile(configPath)
    except:
      discard
  
  if useEnv:
    # Surcharge par variables d'environnement
    if existsEnv("NIMAGENT_SECURITY"):
      let level = case getEnv("NIMAGENT_SECURITY").toLowerAscii():
        of "none": "secNone"
        of "standard": "secStandard"
        of "cognitif": "secCognitif"
        of "always": "secAlways"
        else: "secStandard"
      result["securityLevel"] = %level

    if existsEnv("NIMAGENT_MODEL"):
      result["model"] = %getEnv("NIMAGENT_MODEL")

    if existsEnv("NIMAGENT_VISION"):
      result["enableVision"] = %(getEnv("NIMAGENT_VISION").toLowerAscii() == "true")

proc getApiKey*(provider: string = "openai"): string =
  ## Retrieves the API key from environment variables.
  ##
  ## Supported environment variables:
  ## - OPENAI_API_KEY
  ## - ANTHROPIC_API_KEY
  ## - GEMINI_API_KEY
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

proc getApiKeyOrDefault*(provider: string, default: string = ""): string =
  ## Retrieves the API key, returns default if not found.
  let envVar = case provider.toLowerAscii()
    of "openai": "OPENAI_API_KEY"
    of "anthropic": "ANTHROPIC_API_KEY"
    of "gemini": "GEMINI_API_KEY"
    else: provider.toUpperAscii() & "_API_KEY"
  result = getEnv(envVar, default)

proc getOllamaHost*(): string =
  ## Retrieves the Ollama host (default: http://localhost:11434)
  result = getEnv("OLLAMA_HOST", "http://localhost:11434")

proc getLlamaCppHost*(): string =
  ## Retrieves the llama.cpp host (default: http://localhost:8080)
  result = getEnv("LLAMACPP_HOST", "http://localhost:8080")

proc getLMStudioHost*(): string =
  ## Retrieves the LM Studio host (default: http://localhost:1234/v1)
  result = getEnv("LMSTUDIO_HOST", "http://localhost:1234/v1")
