## Integration tests for tools

import std/[asyncdispatch, json, unittest, tables, strutils]
import nimagent
import nimagent/tools/registry

proc mockToolAction(args: JsonNode): Future[string] {.async.} =
  return "Mock: " & $args

suite "Tools Integration":
  test "Registry with multiple tools":
    let registry = newToolRegistry()

    registry.register(Tool(
      name: "tool_a",
      description: "First tool",
      schema: %*{"type": "object"},
      action: mockToolAction
    ))

    registry.register(Tool(
      name: "tool_b",
      description: "Second tool",
      schema: %*{"type": "object"},
      action: mockToolAction
    ))

    check len(registry.tools) == 2
    check registry.tools.hasKey("tool_a")
    check registry.tools.hasKey("tool_b")

  test "Schema generation for API":
    let registry = newToolRegistry()

    registry.register(Tool(
      name: "add",
      description: "Adds two numbers",
      schema: %*{
        "type": "object",
        "properties": {
          "a": {"type": "integer"},
          "b": {"type": "integer"}
        }
      },
      action: mockToolAction
    ))

    let schema = registry.getToolsSchema()
    check schema != nil
    check schema.kind == JArray
    check schema.len == 1
    check schema[0]["type"].getStr() == "function"
    check schema[0]["function"]["name"].getStr() == "add"

  test "Empty registry returns nil":
    let registry = newToolRegistry()
    let schema = registry.getToolsSchema()
    check schema == nil

  test "Existing tool call":
    let registry = newToolRegistry()

    proc addAction(args: JsonNode): Future[string] {.async.} =
      let a = args["a"].getInt()
      let b = args["b"].getInt()
      return $(a + b)

    registry.register(Tool(
      name: "calculator",
      description: "Calculates a sum",
      schema: %*{},
      action: addAction
    ))

    let result = waitFor registry.callTool("calculator", "{\"a\": 5, \"b\": 3}")
    check result == "8"

  test "Non-existing tool call":
    let registry = newToolRegistry()
    let result = waitFor registry.callTool("nonexistent", "{}")
    check "does not exist" in result

  test "Call with invalid JSON":
    let registry = newToolRegistry()

    proc dummyAction(args: JsonNode): Future[string] {.async.} =
      return "ok"

    registry.register(Tool(
      name: "dummy",
      description: "Test",
      schema: %*{},
      action: dummyAction
    ))

    let result = waitFor registry.callTool("dummy", "{invalid json")
    check "Error" in result

  test "Tool with execution failure":
    let registry = newToolRegistry()

    proc failingAction(args: JsonNode): Future[string] {.async.} =
      raise newException(ValueError, "Simulated error")

    registry.register(Tool(
      name: "failing",
      description: "Tool that fails",
      schema: %*{},
      action: failingAction
    ))

    let result = waitFor registry.callTool("failing", "{}")
    check "Error" in result

  test "Tool replacement":
    let registry = newToolRegistry()

    registry.register(Tool(
      name: "test",
      description: "Version 1",
      schema: %*{},
      action: mockToolAction
    ))

    proc newAction(args: JsonNode): Future[string] {.async.} =
      return "New version"

    registry.register(Tool(
      name: "test",
      description: "Version 2",
      schema: %*{},
      action: newAction
    ))

    check len(registry.tools) == 1
    let tool = registry.tools["test"]
    check tool.description == "Version 2"
