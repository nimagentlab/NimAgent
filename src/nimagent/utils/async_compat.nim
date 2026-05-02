## Async Compatibility Layer - Migration asyncdispatch → Chronos
## =============================================================================
##
## This module provides an abstraction layer to facilitate migration
## from asyncdispatch to Chronos. It enables gradual migration.
##
## Usage:
##   import nimagent/utils/async_compat
##   # Async code works with both backends
##
## To force Chronos: nim c -d:useChronos
## For asyncdispatch: nim c (default, during transition)
##

when defined(useChronos):
  ## Chronos mode (new, performant)
  import chronos
  export chronos

else:
  ## asyncdispatch mode (legacy, during migration)
  import std/[asyncdispatch, asyncnet, httpclient, net]
  export asyncdispatch, asyncnet, httpclient, net

# Common exports
export Future, async, await

## =============================================================================
## Network Error Handling
## =============================================================================

type
  NetworkError* = object of CatchableError
    ## Uniform network error

proc raiseNetworkError*(msg: string) {.noreturn.} =
  ## Raises network error
  raise newException(NetworkError, msg)

## =============================================================================
## Compatibility tests
## =============================================================================

when isMainModule:
  echo "Async compat module loaded"
  when defined(useChronos):
    echo "Mode: CHRONOS"
  else:
    echo "Mode: asyncdispatch (legacy)"
