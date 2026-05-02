## Tests for the tool registry

import std/[asyncdispatch, json, unittest, tables, strutils]
import nimagent/tools/registry

proc dummyTool(args: JsonNode): Future[string] {.async.} =
  return "Result: " & args["input"].getStr()

suite "Tool Registry":
  test "Creating an empty registry":
    let registry = newToolRegistry()
    check len(registry.tools) == 0

  test "Registering and retrieving a tool":
    let registry = newToolRegistry()
    let tool = Tool(
      name: "test_tool",
      description: "A test tool",
      schema: %*{"type": "object", "properties": {}},
      action: dummyTool
    )
    registry.register(tool)
    check registry.tools.len == 1
    check registry.tools.hasKey("test_tool")

  test "Calling non-existent tool":
    let registry = newToolRegistry()
    let result = waitFor registry.callTool("nonexistent", "{}")
    check "does not exist" in result

  test "Tool schema for the API":
    let registry = newToolRegistry()
    let tool = Tool(
      name: "add",
      description: "Adds two numbers",
      schema: %*{"type": "object", "properties": {"a": {"type": "integer"}}},
      action: dummyTool
    )
    registry.register(tool)
    let schema = registry.getToolsSchema()
    check schema.len == 1
