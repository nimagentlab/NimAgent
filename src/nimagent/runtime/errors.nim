## Error handling for nimagent

import std/[strformat, strutils]

type
  ErrorKind* = enum
    ## Standardized error categories
    ekNone
    ekIO              ## Input/output error
    ekNetwork         ## Network error
    ekParse           ## Parsing error
    ekValidation      ## Validation error
    ekLLM             ## LLM provider error
    ekTool            ## Tool execution error
    ekConfig          ## Configuration error
    ekUnknown

  AppError* = object
    ## Standardized error structure
    kind*: ErrorKind
    message*: string
    context*: string

proc newAppError*(kind: ErrorKind, message: string, context: string = ""): AppError =
  AppError(kind: kind, message: message, context: context)

proc formatError*(err: AppError): string =
  ## Formats an error for display
  let ctx = if err.context.len > 0: " [" & err.context & "]" else: ""
  result = err.message & ctx

proc raiseConfigError*(message: string) =
  ## Raises a configuration error
  raise newException(ValueError, "Configuration: " & message)
