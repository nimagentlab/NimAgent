
## test_memory.nim
## Unit tests for MemoryHistory sliding window and persistence.

import std/[os, unittest, json, strutils]
import nimagent/memory/basic_memory
import nimagent/messages

suite "MemoryHistory":
  test "newMemoryHistory and addMessage":
    let mem = newMemoryHistory("You are a tester", maxMessages = 10)
    check mem.systemPrompt == "You are a tester"
    check mem.maxTokensOrMessages == 10
    mem.addMessage(Message(role: User, content: "Hello"))
    check mem.messages.len == 1
    check mem.messages[0].role == User

  test "buildContext includes system prompt":
    let mem = newMemoryHistory("Sys prompt", maxMessages = 5)
    mem.addMessage(Message(role: User, content: "Hi"))
    let ctx = mem.buildContext()
    check ctx.len == 2
    check ctx[0].role == System
    check ctx[0].content == "Sys prompt"
    check ctx[1].role == User

  test "buildContext with RAG":
    let mem = newMemoryHistory("Sys prompt", maxMessages = 5)
    mem.addMessage(Message(role: User, content: "Hi"))
    let ctx = mem.buildContext("RAG context here")
    check ctx.len == 2
    check "RAG context here" in ctx[0].content

  test "sliding window drops oldest messages":
    let mem = newMemoryHistory("Sys", maxMessages = 10)
    for i in 1..15:
      mem.addMessage(Message(role: User, content: "msg " & $i))
    check mem.messages.len == 10
    check mem.messages[0].content == "msg 6"

  test "orphan prevention: Assistant with toolCalls must keep Tool pair":
    let mem = newMemoryHistory("Sys", maxMessages = 5)
    for i in 1..5:
      mem.addMessage(Message(role: User, content: "filler " & $i))
    mem.addMessage(Message(role: Assistant, content: "call calc", toolCalls: @[
      ToolCall(id: "tc1", name: "calc", arguments: "{}")
    ]))
    mem.addMessage(Message(role: Tool, content: "55", toolCallId: "tc1"))
    check mem.messages.len <= 5
    var hasAssistantWithTool = false
    var assistantIdx = -1
    for i, m in mem.messages:
      if m.role == Assistant and m.toolCalls.len > 0:
        hasAssistantWithTool = true
        assistantIdx = i
        break
    if hasAssistantWithTool:
      check assistantIdx + 1 < mem.messages.len  # Tool must follow Assistant
      if assistantIdx + 1 < mem.messages.len:
        check mem.messages[assistantIdx + 1].role == Tool

  test "save and load roundtrip":
    let mem = newMemoryHistory("Agent prompt", maxMessages = 10)
    mem.addMessage(Message(role: User, content: "User msg"))
    mem.addMessage(Message(role: Assistant, content: "Assistant msg", toolCalls: @[ ToolCall(id: "tc1", name: "calc", arguments: "{\"a\":1}") ]))
    mem.addMessage(Message(role: Tool, content: "1", toolCallId: "tc1"))
    let tmpFile = getTempDir() / "test_memory_roundtrip.json"
    mem.saveToDisk(tmpFile)
    defer: removeFile(tmpFile)
    let loaded = loadHistoryFromDisk(tmpFile)
    check loaded.systemPrompt == "Agent prompt"
    check loaded.maxTokensOrMessages == 10
    check loaded.messages.len == 3
    check loaded.messages[0].role == User
    check loaded.messages[1].role == Assistant
    check loaded.messages[1].toolCalls.len == 1
    check loaded.messages[1].toolCalls[0].name == "calc"
    check loaded.messages[2].role == Tool
    check loaded.messages[2].toolCallId == "tc1"
