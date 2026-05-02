## Advanced tests for memory

import std/[unittest, json, os, strutils]
import nimagent/messages
import nimagent/memory/basic_memory

suite "Memory Advanced":
  test "Memory with custom system instruction":
    let mem = newMemoryHistory("You are a Nim expert")
    check mem.systemPrompt == "You are a Nim expert"

  test "Multiple message additions":
    let mem = newMemoryHistory()
    for i in 0..<10:
      mem.addMessage(Message(role: User, content: "Message " & $i))
    check mem.messages.len == 10

  test "Sliding window":
    let mem = newMemoryHistory(maxMessages = 5)
    for i in 0..<20:
      mem.addMessage(Message(role: User, content: "Msg " & $i))

    check mem.messages.len == 5
    # Oldest messages are removed
    check mem.messages[0].content == "Msg 15"
    check mem.messages[4].content == "Msg 19"

  test "Context building with system":
    let mem = newMemoryHistory("You are an AI assistant")
    mem.addMessage(Message(role: User, content: "Hello"))

    let context = mem.buildContext()
    check context.len == 2
    check context[0].role == System
    check context[0].content == "You are an AI assistant"
    check context[1].role == User

  test "Context building with RAG":
    let mem = newMemoryHistory("You are an assistant")
    mem.addMessage(Message(role: User, content: "Question?"))

    let ragContext = "Document found: Nim is a compiled language."
    let ctx = mem.buildContext(ragContext)

    check ctx.len == 2
    check "Document found" in ctx[0].content
    check "Nim is a compiled language" in ctx[0].content

  test "Messages with tool calls":
    let mem = newMemoryHistory()
    var tc = ToolCall(
      id: "call_1",
      name: "read_file",
      arguments: "{}"
    )
    let msg = Message(
      role: Assistant,
      content: "I'm reading the file",
      toolCalls: @[tc]
    )
    mem.addMessage(msg)

    check mem.messages.len == 1
    check mem.messages[0].toolCalls.len == 1
    check mem.messages[0].toolCalls[0].name == "read_file"

  test "Message with tool response":
    let mem = newMemoryHistory()
    let msg = Message(
      role: Tool,
      content: "File content: hello",
      toolCallId: "call_1"
    )
    mem.addMessage(msg)

    check mem.messages[0].role == Tool
    check mem.messages[0].toolCallId == "call_1"

  test "Save and load":
    let testFile = "/tmp/test_memory.json"
    defer: removeFile(testFile)

    let mem = newMemoryHistory("System prompt")
    mem.addMessage(Message(role: User, content: "Test"))
    mem.addMessage(Message(role: Assistant, content: "Response"))

    mem.saveToDisk(testFile)
    check fileExists(testFile)

    let loaded = loadHistoryFromDisk(testFile)
    check loaded.systemPrompt == "System prompt"
    check loaded.messages.len == 2
    check loaded.messages[0].role == User
    check loaded.messages[0].content == "Test"

  test "Loading non-existent file":
    let loaded = loadHistoryFromDisk("/tmp/nonexistent_file_xyz.json")
    check loaded.messages.len == 0

  test "Modifying system prompt":
    let mem = newMemoryHistory("Initial prompt")
    mem.setSystemPrompt("New prompt")
    check mem.systemPrompt == "New prompt"

  test "Empty context without system":
    let mem = newMemoryHistory("")
    let context = mem.buildContext()
    check context.len == 0
