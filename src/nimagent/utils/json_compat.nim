## JSON Compatibility Layer — std/json universal, jsony as optional helper
## =============================================================================
##
## std/json.JsonNode is the single runtime DOM type for the entire framework.
## jsony is available as an *optional* fast serializer for known Nim types when
## compiled with -d:useJsony. It does NOT replace JsonNode.
##
## Usage:
##   import nimagent/utils/json_compat
##   # JsonNode, parseJson, %*, pretty  ← always std/json, always safe
##   # jsonySerialize, jsonyDeserialize ← only when useJsony is defined
##
## =============================================================================

import std/json
export json

when defined(useJsony):
  import jsony

  # ── Optional jsony helpers for typed (de)serialization ──
  proc jsonySerialize*[T](v: T): string =
    ## Fast jsony serializer for structured Nim types.
    ## Does NOT produce JsonNode — use std/json.%* for DOM building.
    jsony.toJson(v)

  proc jsonyDeserialize*[T](s: string; _: typedesc[T]): T =
    ## Fast jsony deserializer into a known Nim type.
    ## For dynamic JSON use std/json.parseJson instead.
    jsony.fromJson(s, T)

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
    echo "Mode: std/json DOM + jsony helpers available"
  else:
    echo "Mode: std/json only"
