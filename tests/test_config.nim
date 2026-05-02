## Tests for configuration

import std/[unittest, os, strutils]
import nimagent/config

suite "Configuration":
  test "getApiKey from environment":
    # Test that getApiKey raises an exception if the key doesn't exist
    var errorRaised = false
    try:
      discard getApiKey("TEST_PROVIDER_NONEXISTENT_12345")
    except ValueError:
      errorRaised = true
    check errorRaised == true

  test "getOllamaHost default":
    # Save current value
    let oldEnv = getEnv("OLLAMA_HOST", "")

    # Without environment variable, should return localhost
    if oldEnv != "":
      os.delEnv("OLLAMA_HOST")
    let host = getOllamaHost()
    check host == "http://localhost:11434"

    # Restore
    if oldEnv != "":
      os.putEnv("OLLAMA_HOST", oldEnv)

  test "getOllamaHost from environment":
    # Save
    let oldEnv = getEnv("OLLAMA_HOST", "")

    # Set a custom value
    os.putEnv("OLLAMA_HOST", "http://custom:8080")
    let host = getOllamaHost()
    check host == "http://custom:8080"

    # Restore
    if oldEnv == "":
      os.delEnv("OLLAMA_HOST")
    else:
      os.putEnv("OLLAMA_HOST", oldEnv)

  test "getApiKey with custom provider name":
    var errorRaised = false
    try:
      discard getApiKey("customprovider")
    except ValueError as e:
      errorRaised = true
      check "CUSTOMPROVIDER_API_KEY" in e.msg
    check errorRaised == true
