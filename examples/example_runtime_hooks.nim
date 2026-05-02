## Example 5: Agent with custom runtime hooks
## Compile with: nim c -d:release 05_runtime_hooks.nim

import std/[asyncdispatch, json]
import nimagent
import nimagent/providers/openai_compatible
import nimagent/runtime/hooks

proc main() {.async.} =
  echo "=== Agent with runtime hooks ==="

  # Custom hooks creation
  var customHooks = defaultHooks()

  # Before inference hook: log and allow
  customHooks.beforeInference = proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.} =
    echo "[HOOK] Inference requested with ", messages.len, " messages"
    return true  # Allow inference

  # After inference hook: log the response
  customHooks.afterInference = proc(agent: Agent, response: Message): Future[void] {.async.} =
    echo "[HOOK] Response received: ", response.content[0 ..< min(50, response.content.len)], "..."

  # Before tool call hook: log
  customHooks.beforeToolCall = proc(agent: Agent, toolName: string, args: JsonNode): Future[bool] {.async.} =
    echo "[HOOK] Tool call: ", toolName, " with args: ", args
    return true  # Allow the call

  # After tool call hook: log the result
  customHooks.afterToolCall = proc(agent: Agent, toolName: string, toolResult: string): Future[void] {.async.} =
    echo "[HOOK] Result from ", toolName, ": ", toolResult[0 ..< min(50, toolResult.len)], "..."

  # Error hook
  customHooks.onError = proc(agent: Agent, error: ref Exception): Future[void] {.async.} =
    echo "[HOOK] Error caught: ", error.msg

  # Provider
  let provider = newOpenAIProvider(
    apiKey = getApiKey("openai"),
    model = "gpt-4o-mini"
  )

  # Agent creation with hooks
  let agent = newAgent(
    name = "HookedAgent",
    provider = provider,
    hooks = customHooks
  )

  # Execution
  let response = await agent.run("Explain what a hook is in programming")
  echo "\nResponse:\n", response

when isMainModule:
  waitFor main()
