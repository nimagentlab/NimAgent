## Tests for basic memory

import std/unittest
import nimagent/messages
import nimagent/memory/basic_memory

suite "Basic Memory":
  test "Creating an empty memory":
    let mem = newMemoryHistory()
    check mem.messages.len == 0

  test "Adding a message":
    let mem = newMemoryHistory()
    mem.addMessage(Message(role: User, content: "Hello"))
    check mem.messages.len == 1
    check mem.messages[0].content == "Hello"

  test "Building context":
    let mem = newMemoryHistory()
    mem.addMessage(Message(role: System, content: "You are an assistant"))
    mem.addMessage(Message(role: User, content: "Say hello"))
    mem.addMessage(Message(role: Assistant, content: "Hello!"))

    let context = mem.buildContext()
    check context.len == 3
    check context[0].role == System

  test "Message limit":
    let mem = newMemoryHistory(maxMessages = 10)
    for i in 0..<100:
      mem.addMessage(Message(role: User, content: "Message " & $i))
    check mem.messages.len == 10  # Should be limited to 10
