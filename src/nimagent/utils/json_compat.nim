## JSON Compatibility Layer - Migration std/json → jsony
## =============================================================================
##
## This module provides an abstraction layer to facilitate migration
## from std/json to jsony (6-7× faster).
##
## Usage:
##   import nimagent/utils/json_compat
##
## To force jsony: nim c -d:useJsony
## For std/json: nim c (default, during transition)
##

when defined(useJsony):
  ## jsony mode (new, fast)
  import jsony
  export jsony

  # JsonNode compatibility type
  type JsonNode* = string

  template parseJson*(s: string): JsonNode = s
  template toJson*(v: auto): string = jsony.toJson(v)
  template `%*`*(v: untyped): string = jsony.toJson(v)
  template pretty*(s: string): string = s

else:
  ## std/json mode (legacy, during migration)
  import std/json
  export json

## =============================================================================
## JSON Error Handling
## =============================================================================

type
  JsonError* = object of CatchableError
    ## Uniform JSON error

proc raiseJsonError*(msg: string) {.noreturn.} =
  ## Raises JSON error
  raise newException(JsonError, msg)

## =============================================================================
## Compatibility Tests
## =============================================================================

when isMainModule:
  echo "JSON compat module loaded"
  when defined(useJsony):
    echo "Mode: JSONY (fast)"
  else:
    echo "Mode: std/json (legacy)"
