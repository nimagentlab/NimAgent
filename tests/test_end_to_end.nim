## End-to-end tests for the complete SDK

import std/[asyncdispatch, json, unittest, tables, strutils]
import nimagent
import nimagent/providers/base

## Configurable Mock Provider for E2E
type
  E2EMockProvider = ref object of LLMProvider
    responses: seq[Message]
    currentIndex: int

proc newE2EMockProvider(): E2EMockProvider =
  E2EMockProvider(responses: @[], currentIndex: 0)

proc addResponse(provider: E2EMockProvider, msg: Message) =
  provider.responses.add(msg)

method generate*(provider: E2EMockProvider, messages: seq[Message],
                 toolsSchema: JsonNode = nil,
                 forceJson: bool = false): Future[Message] {.async.} =
  if provider.currentIndex < provider.responses.len:
    result = provider.responses[provider.currentIndex]
    provider.currentIndex += 1
  else:
    result = Message(role: Assistant, content: "Default response")

method getEmbedding*(provider: E2EMockProvider, text: string): Future[seq[float]] {.async.} =
  return @[1.0, 2.0, 3.0]

suite "End-to-End":
  test "Simple agent conversation":
    let mock = newE2EMockProvider()
    mock.addResponse(Message(role: Assistant, content: "Hello!"))

    let agent = newAgent(
      name = "E2EAgent",
      provider = mock
    )

    let response1 = waitFor agent.run("Say hello")
    check response1 == "Hello!"

  test "Agent with persistent memory":
    let mock = newE2EMockProvider()
    mock.addResponse(Message(role: Assistant, content: "I'm doing well"))
    mock.addResponse(Message(role: Assistant, content: "You said hello"))

    let agent = newAgent(
      name = "MemoryAgent",
      provider = mock
    )

    discard waitFor agent.run("How are you?")
    # Memory keeps the history
    check agent.memory.messages.len >= 2  # User + Assistant

  test "Agent with complete tool calling":
    let mock = newE2EMockProvider()

    # First response: tool request
    var tc = ToolCall(
      id: "call_1",
      name: "calculator",
      arguments: "{\"a\": 5, \"b\": 3}"
    )
    mock.addResponse(Message(
      role: Assistant,
      content: "I'm calculating",
      toolCalls: @[tc]
    ))

    # Second response: final result
    mock.addResponse(Message(role: Assistant, content: "The result is 8"))

    # Create the tool
    proc calcAction(args: JsonNode): Future[string] {.async.} =
      let a = args["a"].getInt()
      let b = args["b"].getInt()
      return $(a + b)

    let tools = newToolRegistry()
    tools.register(Tool(
      name: "calculator",
      description: "Calculates a sum",
      schema: %*{
        "type": "object",
        "properties": {
          "a": {"type": "integer"},
          "b": {"type": "integer"}
        }
      },
      action: calcAction
    ))

    let agent = newAgent(
      name = "ToolAgent",
      provider = mock,
      tools = tools
    )

    let response = waitFor agent.run("Calculate 5 + 3")
    check response == "The result is 8"

    # Check history
    check agent.memory.messages.len >= 4  # User + Assistant(tool_call) + Tool + Assistant(final)

  test "Complete agent configuration":
    let mock = newE2EMockProvider()
    mock.addResponse(Message(role: Assistant, content: "OK"))

    var hookCalled = false
    var hooks = defaultHooks()
    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      hookCalled = true
      return true

    let tools = newToolRegistry()

    let agent = newAgent(
      name = "FullConfigAgent",
      provider = mock,
      tools = tools,
      config = AgentConfig(
        maxSteps: 10,
        enableTracing: false
      ),
      hooks = hooks
    )

    discard waitFor agent.run("Test")
    check hookCalled == true
    check agent.config.maxSteps == 10

  test "Multiple tool calls in a response":
    let mock = newE2EMockProvider()

    var tc1 = ToolCall(id: "call_1", name: "get_weather", arguments: "{\"city\": \"Paris\"}")
    var tc2 = ToolCall(id: "call_2", name: "get_time", arguments: "{}")

    mock.addResponse(Message(
      role: Assistant,
      content: "I'm retrieving the information",
      toolCalls: @[tc1, tc2]
    ))

    mock.addResponse(Message(role: Assistant, content: "Information retrieved"))

    proc weatherAction(args: JsonNode): Future[string] {.async.} =
      return "Sunny in " & args["city"].getStr()

    proc timeAction(args: JsonNode): Future[string] {.async.} =
      return "12:00"

    let tools = newToolRegistry()
    tools.register(Tool(
      name: "get_weather",
      description: "Get weather",
      schema: %*{},
      action: weatherAction
    ))
    tools.register(Tool(
      name: "get_time",
      description: "Get time",
      schema: %*{},
      action: timeAction
    ))

    let agent = newAgent(
      name = "MultiToolAgent",
      provider = mock,
      tools = tools
    )

    let response = waitFor agent.run("Weather and time")
    check response == "Information retrieved"

  test "Agent with step limit":
    let mock = newE2EMockProvider()

    # Simulate a potential infinite loop
    var tc = ToolCall(id: "call_loop", name: "loop", arguments: "{}")
    for i in 0..<100:
      mock.addResponse(Message(
        role: Assistant,
        content: "Loop " & $i,
        toolCalls: @[tc]
      ))

    proc loopAction(args: JsonNode): Future[string] {.async.} =
      return "loop result"

    let tools = newToolRegistry()
    tools.register(Tool(
      name: "loop",
      description: "Loop tool",
      schema: %*{},
      action: loopAction
    ))

    let agent = newAgent(
      name = "LimitedAgent",
      provider = mock,
      tools = tools,
      config = AgentConfig(
        maxSteps: 5,  # Strict limit
        enableTracing: false
      )
    )

    let response = waitFor agent.run("Test loop")
    check "[Limit reached]" in response

  test "Session save and restore":
    let mock = newE2EMockProvider()
    mock.addResponse(Message(role: Assistant, content: "Message 1"))
    mock.addResponse(Message(role: Assistant, content: "Message 2"))

    let agent = newAgent(name = "SessionAgent", provider = mock)

    discard waitFor agent.run("First message")
    discard waitFor agent.run("Second message")

    check agent.memory.messages.len >= 4

    # Save
    agent.memory.saveToDisk("/tmp/test_session.json")

    # Create a new agent with the same memory
    let loadedMem = loadHistoryFromDisk("/tmp/test_session.json")
    check loadedMem.messages.len >= 2
