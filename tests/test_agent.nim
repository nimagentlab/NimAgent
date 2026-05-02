## Tests for the main agent

import std/[asyncdispatch, json, unittest, tables]
import nimagent
import nimagent/providers/base

## Mock Provider for tests
type
  MockProvider = ref object of LLMProvider
    responseQueue: seq[Message]
    callCount: int

proc newMockProvider(): MockProvider =
  MockProvider(responseQueue: @[], callCount: 0)

proc queueResponse(provider: MockProvider, msg: Message) =
  provider.responseQueue.add(msg)

method generate*(provider: MockProvider, messages: seq[Message],
                 toolsSchema: JsonNode = nil,
                 forceJson: bool = false): Future[Message] {.async.} =
  provider.callCount += 1
  if provider.responseQueue.len > 0:
    result = provider.responseQueue[0]
    provider.responseQueue.delete(0)
  else:
    result = Message(role: Assistant, content: "Default mock response")

method getEmbedding*(provider: MockProvider, text: string): Future[seq[float]] {.async.} =
  return @[1.0, 2.0, 3.0]

suite "Agent":
  test "Creating a minimal agent":
    let mock = newMockProvider()
    let agent = newAgent(
      name = "TestAgent",
      provider = mock
    )
    check agent.name == "TestAgent"
    check agent.config.maxSteps == 50

  test "Simple execution with mock":
    let mock = newMockProvider()
    mock.queueResponse(Message(role: Assistant, content: "Hello!"))

    let agent = newAgent(
      name = "TestAgent",
      provider = mock
    )

    let response = waitFor agent.run("Say hello")
    check response == "Hello!"
    check mock.callCount == 1

  test "Agent with custom configuration":
    let mock = newMockProvider()
    let agent = newAgent(
      name = "ConfigAgent",
      provider = mock,
      config = AgentConfig(
        maxSteps: 10,
        enableTracing: false
      )
    )
    check agent.config.maxSteps == 10
    check agent.config.enableTracing == false

  test "Agent with hooks":
    let mock = newMockProvider()
    mock.queueResponse(Message(role: Assistant, content: "OK"))

    var hookCalled = false
    var hooks = defaultHooks()
    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      hookCalled = true
      return true

    let agent = newAgent(
      name = "HookedAgent",
      provider = mock,
      hooks = hooks
    )

    discard waitFor agent.run("Test")
    check hookCalled == true

  test "Agent with tools":
    let mock = newMockProvider()

    # Create a test tool
    proc testAction(args: JsonNode): Future[string] {.async.} =
      return "Result: " & args["input"].getStr()

    let registry = newToolRegistry()
    registry.register(Tool(
      name: "test_tool",
      description: "Test tool",
      schema: %*{"type": "object", "properties": {"input": {"type": "string"}}},
      action: testAction
    ))

    let agent = newAgent(
      name = "ToolAgent",
      provider = mock,
      tools = registry
    )

    check agent.tools.tools.len == 1
    check agent.tools.tools.hasKey("test_tool")
