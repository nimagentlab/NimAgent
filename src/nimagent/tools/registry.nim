import ../utils/async_compat
import ../utils/json_compat
import std/[tables, macros]

when defined(useChronos):
  type
    ToolAction* = proc(args: JsonNode): Future[string] {.closure, raises: [], gcsafe.}
else:
  type
    ToolAction* = proc(args: JsonNode): Future[string] {.closure.}

type
  Tool* = object
    name*: string
    description*: string
    schema*: JsonNode ## JSON Schema of expected arguments
    action*: ToolAction

  ToolRegistry* = ref object
    tools*: Table[string, Tool]

proc newToolRegistry*(): ToolRegistry =
  ToolRegistry(tools: initTable[string, Tool]())

proc register*(registry: ToolRegistry, tool: Tool) =
  registry.tools[tool.name] = tool

proc getToolsSchema*(registry: ToolRegistry): JsonNode =
  ## Returns the JSON expected by the OpenAI API to declare available functions.
  if registry.tools.len == 0: return nil

  var arr = newJArray()
  for name, tool in registry.tools:
    arr.add(%*{
      "type": "function",
      "function": {
        "name": tool.name,
        "description": tool.description,
        "parameters": tool.schema
      }
    })
  return arr

proc callTool*(registry: ToolRegistry, name: string, argsStr: string): Future[
    string] {.async.} =
  ## Executes the tool with arguments provided as JSON by the LLM.
  if registry.tools.hasKey(name):
    let tool = registry.tools[name]
    try:
      let argsJson = parseJson(argsStr)
      return await tool.action(argsJson)
    except CatchableError as e:
      return "Error executing tool '" & name & "': " & e.msg
  else:
    return "Error: Tool '" & name & "' does not exist."

macro llmTool*(description: static[string], procDefNode: untyped): untyped =
  ## Macro that transforms a Nim procedure into a complete LLM Tool.
  ## Generates a function `procNameTool()` that returns the configured `Tool` object.
  var procDef = procDefNode
  if procDef.kind == nnkStmtList and procDef.len > 0:
    procDef = procDef[0]

  procDef.expectKind(nnkProcDef)

  let procName = procDef.name
  let procNameStr = procName.strVal

  let formalParams = procDef.params
  let retType = formalParams[0]
  let isAsync = retType.kind == nnkBracketExpr and retType[0].kind ==
      nnkIdent and retType[0].strVal == "Future"

  var actionBody = newNimNode(nnkStmtList)
  var callNode = newCall(procName)

  var propsStmtList = newNimNode(nnkStmtList)
  var reqAst = newNimNode(nnkBracket)

  let argsJsonIdent = ident("argsJson")
  let propsIdent = ident("props")

  for i in 1 ..< formalParams.len:
    let identDefs = formalParams[i]
    let paramType = identDefs[^2]

    for j in 0 .. identDefs.len - 3:
      let paramName = identDefs[j]
      let paramNameStr = paramName.strVal

      let typeStr = if paramType.kind ==
          nnkIdent: paramType.strVal else: "string"

      let jsonType = case typeStr
        of "int": "integer"
        of "float", "float64", "float32": "number"
        of "bool": "boolean"
        of "string": "string"
        else: "string"

      propsStmtList.add(quote do:
        `propsIdent`[`paramNameStr`] = %*{"type": `jsonType`}
      )

      let hasDefault = identDefs[^1].kind != nnkEmpty
      if not hasDefault:
        reqAst.add(newLit(paramNameStr))

      let getMethodIdent = ident(case typeStr
        of "int": "getInt"
        of "float", "float64", "float32": "getFloat"
        of "bool": "getBool"
        of "string": "getStr"
        else: "getStr")

      if not hasDefault:
        actionBody.add(quote do:
          let `paramName` = `argsJsonIdent`[`paramNameStr`].`getMethodIdent`()
        )
      else:
        let defaultVal = identDefs[^1]
        actionBody.add(quote do:
          let `paramName` = if `argsJsonIdent`.hasKey(`paramNameStr`): `argsJsonIdent`[`paramNameStr`].`getMethodIdent`() else: `defaultVal`
        )

      callNode.add(paramName)

  if isAsync:
    actionBody.add(quote do:
      return $(await `callNode`)
    )
  else:
    actionBody.add(quote do:
      return $(`callNode`)
    )

  let toolGenName = ident(procNameStr & "Tool")

  result = quote do:
    `procDef`

    proc `toolGenName`*(): Tool =
      var `propsIdent` = newJObject()
      `propsStmtList`

      var schema = newJObject()
      schema["type"] = %"object"
      schema["properties"] = `propsIdent`
      schema["required"] = %`reqAst`

      Tool(
        name: `procNameStr`,
        description: `description`,
        schema: schema,
        action: proc(`argsJsonIdent`: JsonNode): Future[string] {.async, closure.} =
        `actionBody`
      )
