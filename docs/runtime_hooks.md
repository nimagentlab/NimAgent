# Runtime hooks

Runtime hooks let you observe or gate parts of the agent lifecycle without modifying the core agent loop.

## Available extension points

| Hook | Runs before/after | Can stop execution? |
|------|-------------------|---------------------|
| `beforeInference` | Before an LLM call | Yes, by returning `false` |
| `afterInference` | After an LLM response | No |
| `beforeToolCall` | Before a tool call | Yes, by returning `false` |
| `afterToolCall` | After a tool result | No |
| `onError` | After a caught error | No |

## Basic example

```nim
import std/asyncdispatch
import nimagent

var hooks = defaultHooks()

hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
  echo "LLM call with ", messages.len, " messages"
  return true

hooks.afterInference = proc(agent: Agent, response: Message): Future[void] {.async.} =
  echo "Response length: ", response.content.len

let agent = newAgent(
  name = "HookedAgent",
  provider = provider,
  hooks = hooks
)
```

## Tool validation example

```nim
hooks.beforeToolCall = proc(agent: Agent, toolName: string, args: JsonNode): Future[bool] {.async.} =
  if toolName == "workspaceWrite" and agent.name != "trusted-writer":
    return false
  return true
```

## Error logging example

```nim
hooks.onError = proc(agent: Agent, error: ref Exception): Future[void] {.async.} =
  echo "Agent error: ", error.msg
```

## Timing example

```nim
import std/monotimes

var startTime: MonoTime

hooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
  startTime = getMonoTime()
  return true

hooks.afterInference = proc(agent: Agent, response: Message): Future[void] {.async.} =
  let duration = getMonoTime() - startTime
  echo "Inference took: ", duration.inMilliseconds, "ms"
```

## Default behavior

If you do not pass hooks, `newAgent` uses empty default hooks and the agent runs normally.

```nim
let agent = newAgent(
  name = "SimpleAgent",
  provider = provider
)
```

## Execution order

```text
1. beforeInference() → true/false
2. LLM call if allowed
3. afterInference()
4. beforeToolCall() → true/false, when tool calls exist
5. Tool execution if allowed
6. afterToolCall()
7. onError(), when a handled error occurs
```

## Limitations

- Hooks run in the same async flow as the agent.
- Blocking hooks should return quickly.
- Hooks are for instrumentation and gating, not for replacing the agent loop.
