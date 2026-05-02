# Tools

`nimagent` provides a small tool system for LLM agents. Tools are registered in a `ToolRegistry` and exposed to providers as JSON schemas.

## Built-in tools

### Echo tool

A side-effect-free tool for testing the tool-calling round trip.

```nim
import nimagent

let registry = newToolRegistry()
registry.register(echoTool())
```

### Calculator tool

A deterministic arithmetic helper for basic expressions.

```nim
registry.register(calculatorTool())
```

### Time tool

Returns the current time in supported formats.

```nim
registry.register(timeNowTool())
```

### Workspace tools

Workspace tools provide constrained file operations under a workspace root.

```nim
registry.register(workspaceListTool())
registry.register(workspaceReadTool())
registry.register(workspaceWriteTool())
```

Safety rules include:

- absolute paths rejected;
- path traversal rejected;
- hidden files rejected by default;
- read/write byte limits;
- overwrite disabled by default;
- no delete, chmod, move, or rename operation.

## Creating custom tools

Use the `llmTool` macro:

```nim
import std/asyncdispatch
import nimagent

llmTool "Description of what this tool does":
  proc myTool(param1: string, param2: int = 10): Future[string] {.async.} =
    return "Result: " & param1 & " " & $param2

let registry = newToolRegistry()
registry.register(myToolTool())
```

The generated constructor is named after the procedure plus `Tool`. For `myTool`, the generated constructor is `myToolTool()`.

## Manual tool definition

You can also define a tool manually:

```nim
import std/[asyncdispatch, json]
import nimagent

proc addTool(): Tool =
  let schema = %*{
    "type": "object",
    "properties": {
      "a": {"type": "integer"},
      "b": {"type": "integer"}
    },
    "required": @["a", "b"]
  }

  proc action(args: JsonNode): Future[string] {.async.} =
    return $(args["a"].getInt() + args["b"].getInt())

  Tool(
    name: "add",
    description: "Adds two integers",
    schema: schema,
    action: action
  )
```

## Tool registry

```nim
let registry = newToolRegistry()
registry.register(echoTool())
registry.register(calculatorTool())

let schema = registry.getToolsSchema()
let result = await registry.callTool("calculator", """{"expression":"2 + 2"}""")
```

## Security note

Tools are code execution boundaries. Keep the initial public tool surface small, explicit, and easy to audit.
