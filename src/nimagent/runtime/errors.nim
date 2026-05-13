## nimagent - Runtime Errors
## Unified error handling for the framework.
## Single source of truth for error types.

import std/[strformat, strutils, json]
import ../utils/async_compat

type
  ErrorKind* = enum
    ekNone
    ekIO              ## Input/output error
    ekNetwork         ## Network error
    ekParse           ## Parsing error
    ekValidation      ## Validation error
    ekLLM             ## LLM provider error
    ekTool            ## Tool execution error
    ekConfig          ## Configuration error
    ekEmbedding       ## Embedding error
    ekSearch          ## Vector search error
    ekMemory          ## Memory management error
    ekUnknown

  AppError* = object
    kind*: ErrorKind
    message*: string
    context*: string
    sourceError*: string

proc newAppError*(kind: ErrorKind, message: string, context: string = ""): AppError =
  AppError(kind: kind, message: message, context: context)

proc wrapException*(e: ref Exception, context: string, defaultKind: ErrorKind = ekUnknown): AppError =
  ## Converts a Nim exception into an AppError.
  ## Auto-detects certain error categories.
  let msg = e.msg
  var kind = defaultKind

  if "json" in msg.toLowerAscii() or "parse" in msg.toLowerAscii():
    kind = ekParse
  elif "http" in msg.toLowerAscii() or "connection" in msg.toLowerAscii():
    kind = ekNetwork
  elif "io" in msg.toLowerAscii() or "file" in msg.toLowerAscii():
    kind = ekIO
  elif "embed" in msg.toLowerAscii():
    kind = ekEmbedding
  elif "llm" in msg.toLowerAscii() or "api" in msg.toLowerAscii():
    kind = ekLLM

  AppError(kind: kind, message: fmt"Error in {context}", context: context, sourceError: msg)

proc formatError*(err: AppError): string =
  let ctx = if err.context.len > 0: fmt" [{err.context}]" else: ""
  let src = if err.sourceError.len > 0: fmt" : {err.sourceError}" else: ""
  fmt"{err.message}{ctx}{src}"

proc toJsonError*(err: AppError): JsonNode =
  %*{
    "error": true,
    "kind": $err.kind,
    "message": err.message,
    "context": err.context,
    "source": err.sourceError
  }

proc raiseConfigError*(message: string) =
  raise newException(ValueError, "Configuration: " & message)

# ── Async-safe wrappers ──

proc catchAsync*(context: string, body: proc(): Future[string] {.async.}): Future[string] {.async.} =
  ## Catches all exceptions and returns a formatted error string.
  try:
    return await body()
  except Exception as e:
    let err = wrapException(e, context)
    return "Error: " & formatError(err)

proc wrapToolAction*(context: string, impl: proc(): Future[string] {.async.}): Future[string] {.async.} =
  ## ToolAction-specific wrapper. Guarantees no unhandled exceptions.
  try:
    return await impl()
  except Exception as e:
    return "Error executing '" & context & "': " & e.msg