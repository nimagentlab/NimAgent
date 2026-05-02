import ../messages
import std/strutils

type
  MemoryHistory* = ref object
    systemPrompt*: string
    messages*: seq[Message]
    maxTokensOrMessages*: int

proc newMemoryHistory*(systemPrompt: string = "You are a helpful AI assistant.", maxMessages: int = 50): MemoryHistory =
  ## Creates a new memory with a basic system instruction.
  MemoryHistory(
    systemPrompt: systemPrompt, 
    messages: @[], 
    maxTokensOrMessages: maxMessages
  )

proc addMessage*(mem: MemoryHistory, msg: Message) =
  ## Adds a message to the history. Manages maximum size to avoid context overflow.
  mem.messages.add(msg)
  ## Very simple sliding window mechanism
  if mem.messages.len > mem.maxTokensOrMessages:
    mem.messages.delete(0)

proc setSystemPrompt*(mem: MemoryHistory, prompt: string) =
  ## Modifies the main system instruction.
  mem.systemPrompt = prompt

proc buildContext*(mem: MemoryHistory, ragContext: string = ""): seq[Message] =
  ## Builds the final message array to send to the LLM.
  ## Dynamically injects RAG information into the system instruction.
  ## Avoids duplicate system messages if the first message in history is already a System message.
  var ctx: seq[Message] = @[]

  ## 1. System Prompt Preparation
  var finalSysPrompt = mem.systemPrompt

  ## If we have RAG context (found documents), inject it here
  if ragContext.strip() != "":
    finalSysPrompt &= "\n\n--- CONTEXT INFORMATION (RAG) ---\n"
    finalSysPrompt &= ragContext
    finalSysPrompt &= "\n----------------------------------------\n"
    finalSysPrompt &= "Use this information to answer the user's question."

  ## Check if the first message in history is already a System message
  let hasSystemInHistory = mem.messages.len > 0 and mem.messages[0].role == System

  ## Only add systemPrompt if it's not empty and there's no System message in history
  if finalSysPrompt != "" and not hasSystemInHistory:
    ctx.add(Message(role: System, content: finalSysPrompt))

  ## 2. Adding message history
  ctx.add(mem.messages)
  return ctx

import std/[json, os]

proc saveToDisk*(mem: MemoryHistory, filepath: string) =
  ## Persists short-term memory (History + Procedural) to a JSON file.
  var jMessages = newJArray()
  for m in mem.messages:
    var jMsg = %*{ "role": $m.role, "content": m.content, "toolCallId": m.toolCallId }
    var jTc = newJArray()
    for tc in m.toolCalls:
      jTc.add(%*{ "id": tc.id, "name": tc.name, "arguments": tc.arguments })
    jMsg["toolCalls"] = jTc
    jMessages.add(jMsg)
    
  let data = %*{
    "systemPrompt": mem.systemPrompt,
    "maxTokensOrMessages": mem.maxTokensOrMessages,
    "messages": jMessages
  }
  writeFile(filepath, data.pretty())

proc loadHistoryFromDisk*(filepath: string): MemoryHistory =
  ## Restores short-term memory from a JSON file.
  if not fileExists(filepath): return newMemoryHistory()
  let data = parseFile(filepath)
  var mem = newMemoryHistory(data["systemPrompt"].getStr(), data["maxTokensOrMessages"].getInt())
  for jMsg in data["messages"]:
    let roleStr = jMsg["role"].getStr()
    let role = case roleStr:
      of "System": System
      of "User": User
      of "Assistant": Assistant
      of "Tool": Tool
      else: User
    var msg = Message(role: role, content: jMsg["content"].getStr(), toolCallId: jMsg["toolCallId"].getStr())
    for tc in jMsg["toolCalls"]:
      msg.toolCalls.add(ToolCall(id: tc["id"].getStr(), name: tc["name"].getStr(), arguments: tc["arguments"].getStr()))
    mem.messages.add(msg)
  return mem
