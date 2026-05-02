## Tests for runtime (trace, hooks)

import std/[asyncdispatch, json, unittest]
import nimagent
import nimagent/agent
import nimagent/runtime/trace
import nimagent/runtime/hooks

suite "Runtime":
  test "Default hooks are nil":
    let hooks = defaultHooks()
    check hooks.beforeInference == nil
    check hooks.afterInference == nil
    check hooks.beforeToolCall == nil
    check hooks.afterToolCall == nil
    check hooks.onError == nil

  test "Default configuration":
    let cfg = defaultConfig()
    check cfg.maxSteps == 50
    check cfg.maxContextChars == 60000
    check cfg.enableTracing == true

  test "beforeInference hook blocking":
    var hooks = defaultHooks()
    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      return false  # Blocks inference

    check hooks.beforeInference != nil

  test "beforeToolCall hook blocking":
    var hooks = defaultHooks()
    hooks.beforeToolCall = proc(agent: Agent, toolName: string, args: JsonNode): Future[bool] {.async.} =
      return false  # Blocks tool call

    let shouldCallTool = waitFor hooks.beforeToolCall(nil, "test_tool", %*{})
    check shouldCallTool == false

  test "onError hook captures error":
    var errorWasCaptured = false
    var hooks = defaultHooks()
    hooks.onError = proc(agent: Agent, error: ref Exception): Future[void] {.async.} =
      errorWasCaptured = true

    # Simulated call
    waitFor hooks.onError(nil, newException(ValueError, "Test error"))
    check errorWasCaptured == true

  test "Trace functions exist":
    # These functions return nothing, we just check they compile
    traceInfo("Test", "Info message")
    traceError("Test", "Error message")
    traceAction("Test", "Test action")
    traceAgent("Test", "Label", "Content")

  test "Agent with disabled tracing":
    let cfg = AgentConfig(
      maxSteps: 10,
      enableTracing: false
    )
    check cfg.enableTracing == false

  test "Multiple hooks can be defined":
    var hooks = defaultHooks()
    var callCount = 0

    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      callCount += 1
      return true

    hooks.afterInference = proc(agent: Agent, response: Message): Future[void] {.async.} =
      callCount += 1

    hooks.beforeToolCall = proc(agent: Agent, toolName: string, args: JsonNode): Future[bool] {.async.} =
      callCount += 1
      return true

    hooks.afterToolCall = proc(agent: Agent, toolName: string, toolResult: string): Future[void] {.async.} =
      callCount += 1

    # Check that all hooks are defined
    check hooks.beforeInference != nil
    check hooks.afterInference != nil
    check hooks.beforeToolCall != nil
    check hooks.afterToolCall != nil

    # Execute them
    discard waitFor hooks.beforeInference(nil, @[])
    waitFor hooks.afterInference(nil, Message(role: Assistant, content: "Test"))
    discard waitFor hooks.beforeToolCall(nil, "test", %*{})
    waitFor hooks.afterToolCall(nil, "test", "result")

    check callCount == 4

  test "before/after hook chain":
    var sequence: seq[string] = @[]
    var hooks = defaultHooks()

    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      sequence.add("before")
      return true

    hooks.afterInference = proc(agent: Agent, response: Message): Future[void] {.async.} =
      sequence.add("after")

    discard waitFor hooks.beforeInference(nil, @[])
    waitFor hooks.afterInference(nil, Message(role: Assistant, content: ""))

    check sequence.len == 2
    check sequence[0] == "before"
    check sequence[1] == "after"
