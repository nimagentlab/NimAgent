## Tests for the messages module

import std/unittest
import nimagent/messages

suite "Messages":
  test "Creating a user message":
    let msg = Message(role: User, content: "Hello")
    check msg.role == User
    check msg.content == "Hello"
    check msg.toolCalls.len == 0

  test "Creating an assistant message with tool calls":
    var tc = ToolCall(
      id: "call_123",
      name: "read_file",
      arguments: "{\"path\": \"/tmp/test.txt\"}"
    )
    let msg = Message(
      role: Assistant,
      content: "I will read the file",
      toolCalls: @[tc]
    )
    check msg.role == Assistant
    check msg.toolCalls.len == 1
    check msg.toolCalls[0].name == "read_file"

  test "Checking roles":
    check $System == "System"
    check $User == "User"
    check $Assistant == "Assistant"
    check $Tool == "Tool"
