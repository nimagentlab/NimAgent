## Echo Tool - Debug/Test Tool
## For testing the tool-calling roundtrip

import ../../utils/async_compat
import ../../utils/json_compat
import ../registry

llmTool "Echo tool for debugging. Returns the input arguments as a formatted string. Useful for testing the tool-calling roundtrip without side effects.":
  proc echoMessage(message: string): Future[string] {.async.} =
    ## Simple echo for testing tool calls
    return "Echo: " & message


proc echoTool*(): Tool =
  ## Stable public constructor for the built-in echo tool.
  result = echoMessageTool()
  result.name = "echo"
