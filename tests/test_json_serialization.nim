## Tests for JSON serialization

import std/[unittest, json]
import nimagent/messages
import nimagent/memory/basic_memory

suite "JSON Serialization":
  test "User message to JSON":
    let msg = Message(role: User, content: "Hello")
    let json = %*{
      "role": $msg.role,
      "content": msg.content,
      "toolCallId": msg.toolCallId
    }
    check json["role"].getStr() == "User"
    check json["content"].getStr() == "Hello"

  test "Message with tool calls to JSON":
    let tc = ToolCall(
      id: "call_123",
      name: "read_file",
      arguments: "{\"path\":\"/tmp/test.txt\"}"
    )
    let msg = Message(
      role: Assistant,
      content: "I'm going to read",
      toolCalls: @[tc]
    )

    # Manual serialization
    var toolCallsJson = newJArray()
    for t in msg.toolCalls:
      toolCallsJson.add(%*{
        "id": t.id,
        "name": t.name,
        "arguments": t.arguments
      })

    let json = %*{
      "role": $msg.role,
      "content": msg.content,
      "toolCalls": toolCallsJson
    }

    check json["toolCalls"].len == 1
    check json["toolCalls"][0]["name"].getStr() == "read_file"

  test "Tool schema JSON valid":
    let schema = %*{
      "type": "object",
      "properties": {
        "query": {
          "type": "string",
          "description": "The search query"
        },
        "limit": {
          "type": "integer",
          "description": "Maximum number of results"
        }
      },
      "required": @["query"]
    }

    check schema["type"].getStr() == "object"
    check schema["properties"].hasKey("query")
    check schema["properties"].hasKey("limit")
    check schema["required"][0].getStr() == "query"

  test "Tool arguments JSON parsing":
    let argsStr = "{\"a\": 10, \"b\": 20, \"name\": \"test\"}"
    let args = parseJson(argsStr)

    check args["a"].getInt() == 10
    check args["b"].getInt() == 20
    check args["name"].getStr() == "test"

  test "Empty JSON parsing":
    let args = parseJson("{}")
    check args.kind == JObject
    check args.len == 0

  test "Invalid JSON error capture":
    var errorCaught = false
    try:
      discard parseJson("{invalid}")
    except JsonParsingError:
      errorCaught = true
    check errorCaught == true

  test "Tools table to JSON":
    let toolsArray = %*[
      {
        "type": "function",
        "function": {
          "name": "add",
          "description": "Addition",
          "parameters": {
            "type": "object",
            "properties": {}
          }
        }
      },
      {
        "type": "function",
        "function": {
          "name": "sub",
          "description": "Subtraction",
          "parameters": {
            "type": "object",
            "properties": {}
          }
        }
      }
    ]

    check toolsArray.len == 2
    check toolsArray[0]["function"]["name"].getStr() == "add"
    check toolsArray[1]["function"]["name"].getStr() == "sub"

  test "Role enum to string conversion":
    check $System == "System"
    check $User == "User"
    check $Assistant == "Assistant"
    check $Tool == "Tool"
