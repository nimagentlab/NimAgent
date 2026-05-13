## test_react.nim
## Unit tests for the ReAct cycle using a MockProvider.

import std/[json, asyncdispatch, unittest, tables, strutils]
import nimagent/agent
import nimagent/messages
import nimagent/providers/base
import nimagent/memory/basic_memory
import nimagent/tools/registry
import nimagent/tools/permissions
import nimagent/core/security

# =============================================================================
# MockProvider — Predictable LLM for testing
# =============================================================================

type MockProvider = ref object of LLMProvider
  responses: seq[Message]
  callIndex: int

method generate*(p: MockProvider, messages: seq[Message],
    toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  let idx = p.callIndex
  p.callIndex += 1
  if idx < p.responses.len:
    return p.responses[idx]
  return Message(role: Assistant, content: "Default")

method countTokens*(p: MockProvider, text: string): int =
  text.len div 4

method getMaxContextTokens*(p: MockProvider): Future[int] {.async.} =
  return 8192

proc newMockProvider(responses: seq[Message]): MockProvider =
  MockProvider(responses: responses, callIndex: 0)

# =============================================================================
# FailingProvider — Always raises an error
# =============================================================================

type FailingProvider = ref object of LLMProvider

method generate*(p: FailingProvider, messages: seq[Message],
    toolsSchema: JsonNode = nil, forceJson: bool = false): Future[Message] {.async.} =
  raise newException(IOError, "network down")

# =============================================================================
# Test suite
# =============================================================================

suite "ReAct cycle":
  test "simple chat returns text directly":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "Hello user")
    ])
    let agent = newAgent("Test", provider, config = defaultConfig())
    let result = waitFor agent.chat("Hi")
    check result == "Hello user"
    check agent.memory.messages.len == 2  # User + Assistant

  test "tool call cycle executes tool and returns final answer":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "", toolCalls: @[
        ToolCall(id: "tc1", name: "calc", arguments: "{\"a\": 2, \"b\": 3}")
      ]),
      Message(role: Assistant, content: "The answer is 5")
    ])
    let agent = newAgent("Test", provider, config = defaultConfig())
    agent.tools.register(Tool(
      name: "calc",
      description: "Add two numbers",
      schema: newJObject(),
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        let a = args["a"].getInt()
        let b = args["b"].getInt()
        return $(a + b)
    ))
    let result = waitFor agent.chat("What is 2+3?")
    check result == "The answer is 5"
    check agent.memory.messages.len == 4  # User + Assistant(tool) + Tool + Assistant(final)

  test "beforeToolCall hook can block execution":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "", toolCalls: @[
        ToolCall(id: "tc1", name: "dangerous", arguments: "{}")
      ]),
      Message(role: Assistant, content: "Tool was blocked")
    ])
    let agent = newAgent("Test", provider, config = defaultConfig())
    agent.tools.register(Tool(
      name: "dangerous",
      description: "Should not run",
      schema: newJObject(),
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        return "SHOULD NOT SEE THIS"
    ))
    var blocked = false
    agent.hooks.beforeToolCall = proc(a: Agent, toolName: string,
        args: JsonNode): Future[bool] {.async.} =
      if toolName == "dangerous":
        blocked = true
        return false
      return true
    let result = waitFor agent.chat("Run dangerous")
    check blocked == true
    check result == "Tool was blocked"
    ## The dangerous tool result should NOT be in memory
    var hasDangerousResult = false
    for m in agent.memory.messages:
      if m.role == Tool and m.content == "SHOULD NOT SEE THIS":
        hasDangerousResult = true
    check hasDangerousResult == false

  test "afterInference hook is called":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "Response")
    ])
    let agent = newAgent("Test", provider, config = defaultConfig())
    var hookCalled = false
    agent.hooks.afterInference = proc(a: Agent, response: Message): Future[void] {.async.} =
      hookCalled = true
    discard waitFor agent.chat("Ping")
    check hookCalled == true

  test "onError hook fires on provider failure":
    let agent = newAgent("Test", FailingProvider(), config = defaultConfig())
    var errorHookCalled = false
    agent.hooks.onError = proc(a: Agent, error: ref Exception): Future[void] {.async.} =
      errorHookCalled = true
    let result = waitFor agent.chat("Ping")
    check errorHookCalled == true
    check "Error:" in result

  test "maxSteps limits the loop":
    let provider = newMockProvider(@[
      Message(role: Assistant, content: "", toolCalls: @[
        ToolCall(id: "tc1", name: "noop", arguments: "{}")
      ])
    ])
    let agent = newAgent("Test", provider, config = defaultConfig())
    agent.config.maxSteps = 2
    agent.tools.register(Tool(
      name: "noop",
      description: "Does nothing",
      schema: newJObject(),
      permissions: defaultSafePermissions(),
      action: proc(args: JsonNode): Future[string] {.async.} =
        return "done"
    ))
    let result = waitFor agent.chat("Loop")
    check "[Limit reached after 2 steps]" in result
