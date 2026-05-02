

type
  Role* = enum
    System, User, Assistant, Tool
    
  ToolCall* = object
    id*: string
    name*: string
    arguments*: string # JSON string
    
  Message* = object
    role*: Role
    content*: string
    toolCallId*: string # Used when role is Tool to link a tool result
    toolCalls*: seq[ToolCall] # Used when the assistant requests tool calls
    

    # llm*: LLMProvider
    # memory*: MemoryHistory
    # tools*: ToolRegistry
