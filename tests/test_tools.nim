## test_tools.nim
## Unit tests for the ToolRegistry and llmTool macro.

import std/[json, asyncdispatch, unittest, tables, strutils]
import nimagent/tools/registry
import nimagent/tools/permissions
import nimagent/utils/json_compat
import nimagent/utils/async_compat

# =============================================================================
# llmTool macro definitions — must be at top level (export not allowed in templates)
# =============================================================================

llmTool "Returns the sum of two integers.":
  proc testAdd*(a: int, b: int): string =
    return $(a + b)

llmTool "Greets someone, optionally with a suffix.":
  proc testGreet*(name: string, suffix: string = "!"): string =
    return "Hello " & name & suffix

# =============================================================================
# Test suites
# =============================================================================

suite "ToolRegistry":
  test "newToolRegistry creates empty registry":
    let reg = newToolRegistry()
    check len(reg.tools) == 0
    check isNil(reg.getToolsSchema())

  test "register and getToolsSchema":
    let reg = newToolRegistry()
    reg.register(Tool(
      name: "echo",
      description: "Echoes input",
      schema: %*{"type": "object", "properties": {"msg": {"type": "string"}}},
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        return args["msg"].getStr()
    ))
    check len(reg.tools) == 1
    let schema = reg.getToolsSchema()
    check schema.kind == JArray
    check schema.len == 1
    check schema[0]["function"]["name"].getStr() == "echo"

  test "callTool success":
    let reg = newToolRegistry()
    reg.register(Tool(
      name: "add",
      description: "Add two numbers",
      schema: %*{"type": "object", "properties": {"a": {"type": "integer"}, "b": {"type": "integer"}}},
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        let a = args["a"].getInt()
        let b = args["b"].getInt()
        return $(a + b)
    ))
    let result = waitFor reg.callTool("add", "{\"a\": 2, \"b\": 3}")
    check result == "5"

  test "callTool missing tool":
    let reg = newToolRegistry()
    let result = waitFor reg.callTool("missing", "{}")
    check "does not exist" in result

  test "callTool action error":
    let reg = newToolRegistry()
    reg.register(Tool(
      name: "fail",
      description: "Always fails",
      schema: newJObject(),
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        raise newException(ValueError, "boom")
    ))
    let result = waitFor reg.callTool("fail", "{}")
    check "Error executing tool" in result
    check "boom" in result

suite "llmTool macro":
  test "macro generates Tool with correct schema":
    let tool = testAddTool()
    check tool.name == "testAdd"
    check tool.description == "Returns the sum of two integers."
    check tool.schema["type"].getStr() == "object"
    check tool.schema["properties"].hasKey("a")
    check tool.schema["properties"].hasKey("b")
    check tool.schema["required"].len == 2

    let result = waitFor tool.action(%*{"a": 10, "b": 20})
    check result == "30"

  test "macro handles optional parameters":
    let tool = testGreetTool()
    let r1 = waitFor tool.action(%*{"name": "Nim"})
    check r1 == "Hello Nim!"
    let r2 = waitFor tool.action(%*{"name": "Nim", "suffix": "?"})
    check r2 == "Hello Nim?"
