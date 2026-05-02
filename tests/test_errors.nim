## Tests for error handling

import std/[asyncdispatch, json, unittest, strutils]
import nimagent
import nimagent/errors
import nimagent/tools/registry

suite "Error Handling":
  test "AppError can be created":
    let err = newAppError(ekLLM, "Provider unavailable")
    check err.kind == ekLLM
    check err.message == "Provider unavailable"

  test "AppError with context":
    let err = newAppError(ekTool, "Execution failed", "tool_name")
    check err.kind == ekTool
    check err.message == "Execution failed"
    check err.context == "tool_name"

  test "ErrorKind variants":
    check ord(ekNone) >= 0
    check ord(ekIO) >= 0
    check ord(ekNetwork) >= 0
    check ord(ekParse) >= 0
    check ord(ekValidation) >= 0
    check ord(ekLLM) >= 0
    check ord(ekTool) >= 0
    check ord(ekConfig) >= 0
    check ord(ekUnknown) >= 0

  test "formatError without context":
    let err = newAppError(ekNetwork, "Connection timeout")
    let formatted = formatError(err)
    check formatted == "Connection timeout"

  test "formatError with context":
    let err = newAppError(ekTool, "Failed to execute", "calculator")
    let formatted = formatError(err)
    check "Failed to execute" in formatted
    check "calculator" in formatted

  test "raiseConfigError raises exception":
    var raised = false
    try:
      raiseConfigError("Invalid API key")
    except ValueError as e:
      raised = true
      check "Configuration" in e.msg
      check "Invalid API key" in e.msg
    check raised == true

  test "Tool execution error handling":
    let registry = newToolRegistry()

    proc failingTool(args: JsonNode): Future[string] {.async.} =
      raise newException(ValueError, "Tool failed!")

    registry.register(Tool(
      name: "failing",
      description: "Always fails",
      schema: %*{},
      action: failingTool
    ))

    let result = waitFor registry.callTool("failing", "{}")
    check "Error" in result
    check "Tool failed" in result

  test "Tool not found error":
    let registry = newToolRegistry()
    let result = waitFor registry.callTool("nonexistent", "{}")
    check "does not exist" in result
    check "nonexistent" in result

  test "Invalid JSON in tool arguments":
    let registry = newToolRegistry()

    proc dummyTool(args: JsonNode): Future[string] {.async.} =
      return "ok"

    registry.register(Tool(
      name: "dummy",
      description: "Test tool",
      schema: %*{},
      action: dummyTool
    ))

    # Invalid JSON
    let result = waitFor registry.callTool("dummy", "{broken json")
    check "Error" in result

  test "Empty arguments handling":
    let registry = newToolRegistry()

    proc acceptEmpty(args: JsonNode): Future[string] {.async.} =
      return "Empty is ok"

    registry.register(Tool(
      name: "empty_ok",
      description: "Accepts empty",
      schema: %*{},
      action: acceptEmpty
    ))

    let result = waitFor registry.callTool("empty_ok", "{}")
    check result == "Empty is ok"

  test "Missing required field in JSON":
    let registry = newToolRegistry()

    proc needsField(args: JsonNode): Future[string] {.async.} =
      if not args.hasKey("required_field"):
        return "Error: missing required_field"
      return "Success"

    registry.register(Tool(
      name: "needs_field",
      description: "Needs a field",
      schema: %*{},
      action: needsField
    ))

    let result = waitFor registry.callTool("needs_field", "{\"other\": 1}")
    check "Error" in result
