## Tests for runtime hooks

import std/[asyncdispatch, json, unittest]
import nimagent/messages
import nimagent/agent

suite "Runtime Hooks":
  test "Creating default hooks":
    let hooks = defaultHooks()
    check hooks.beforeInference == nil
    check hooks.afterInference == nil
    check hooks.beforeToolCall == nil
    check hooks.afterToolCall == nil
    check hooks.onError == nil

  test "Custom hooks execution":
    var hooks = defaultHooks()
    var called = false

    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      called = true
      return true

    let result = waitFor hooks.beforeInference(nil, @[])
    check result == true
    check called == true

  test "Custom hooks":
    var hooks = defaultHooks()
    var called = false

    hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
      called = true
      return true

    check hooks.beforeInference != nil
    let result = waitFor hooks.beforeInference(nil, @[])
    check result == true
    check called == true
