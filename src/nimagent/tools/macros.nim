import ../utils/async_compat
import std/[macros, json, strformat]
import ./registry

macro agentTool*(desc: static string, procDef: untyped): untyped =
  ## Magic macro that transforms a standard Nim function into a `Tool`
  ## understandable by the agent (Generates the JSON Schema and parsing Wrapper).
  
  procDef.expectKind(nnkProcDef)
  let procName = procDef.name
  let procNameStr = $procName
  
  let params = procDef.params
  
  var propsStmt = newStmtList()
  var reqsStmt = newStmtList()
  var callArgs = newNimNode(nnkArgList)
  
  # Iterating through function parameters (Skip 1st which is the return type)
  for i in 1 ..< params.len:
    let identDef = params[i]
    let pType = identDef[^2]
    
    # Handling multiple definitions like `a, b: int`
    for j in 0 ..< identDef.len - 2:
      let pName = identDef[j]
      let pNameStr = $pName
      let typeStr = $pType
      
      # Mapping Nim types -> JSON Schema types
      var jsonType = "string"
      if typeStr == "int": jsonType = "integer"
      elif typeStr == "float": jsonType = "number"
      elif typeStr == "bool": jsonType = "boolean"
      
      # Generating AST code to fill the JSON schema
      propsStmt.add parseStmt(fmt"""properties["{pNameStr}"] = %*{{ "type": "{jsonType}" }}""")
      reqsStmt.add parseStmt(fmt"""required.add(%"{pNameStr}")""")
      
      # Determining the JSON parsing method (getInt, getStr, etc.)
      var getMethod = "getStr"
      if typeStr == "int": getMethod = "getInt"
      elif typeStr == "float": getMethod = "getFloat"
      elif typeStr == "bool": getMethod = "getBool"
      
      # Generating the argument to call the original function
      let argExpr = parseExpr(fmt"""args["{pNameStr}"].{getMethod}()""")
      callArgs.add(argExpr)
      
  # Creating the call to the original function: `myFunction(arg1, arg2)`
  let callProc = newCall(procName, callArgs)
  let builderName = ident("buildTool_" & procNameStr)
  
  # Putting it all together!
  result = quote do:
    # 1. Inject the original procedure definition so it exists
    `procDef`
    
    # 2. Create a hidden constructor function
    proc `builderName`(): Tool =
      var properties = newJObject()
      var required = newJArray()
      
      `propsStmt`
      `reqsStmt`
      
      let schema = %*{
        "type": "object",
        "properties": properties,
        "required": required
      }
      
      # The wrapper that will be called by the framework (takes a JsonNode, returns a string)
      proc actionWrapper(args: JsonNode): Future[string] {.async, closure, gcsafe.} =
        try:
          # We assume the user function is async and returns Future[string]
          return await `callProc`
        except Exception as e:
          return "Error during tool execution: " & e.msg
          
      return Tool(
        name: `procNameStr`,
        description: `desc`,
        schema: schema,
        action: actionWrapper
      )
      
    # 3. The macro resolves to the constructor call, returning a Tool
    `builderName`()
