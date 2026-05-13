## nimagent - Core Message Types
## Unified message system for the entire framework.
## This is the SINGLE source of truth for Message, Role, ToolCall.

type
  Role* = enum
    System, User, Assistant, Tool

  ToolCall* = object
    id*: string
    name*: string
    arguments*: string  ## JSON string

  Message* = object
    role*: Role
    content*: string
    images*: seq[string]       ## Base64 encoded images or URLs for Vision
    toolCallId*: string        ## Used when role is Tool to link a tool result
    toolCalls*: seq[ToolCall]  ## Used when the Assistant requests tool calls