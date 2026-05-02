## nimagent - Main agent
## Simplified ReAct engine for compiled LLM agents

import ./utils/async_compat
import ./utils/http_compat
import ./utils/json_compat
import ./messages
import ./providers/base
import ./memory/basic_memory
import ./tools/registry
import ./runtime/trace
import std/tables

export messages, base, basic_memory, registry

type
  Agent* = ref object
    name*: string
    provider*: LLMProvider
    memory*: MemoryHistory
    tools*: ToolRegistry
    config*: AgentConfig
    hooks*: RuntimeHooks

  AgentConfig* = object
    maxSteps*: int
    maxContextChars*: int
    enableTracing*: bool

  RuntimeHooks* = ref object
    beforeInference*: proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.}
    afterInference*: proc(agent: Agent, response: Message): Future[void] {.async.}
    beforeToolCall*: proc(agent: Agent, toolName: string, args: JsonNode): Future[bool] {.async.}
    afterToolCall*: proc(agent: Agent, toolName: string, result: string): Future[void] {.async.}
    onError*: proc(agent: Agent, error: ref Exception): Future[void] {.async.}

proc defaultConfig*(): AgentConfig =
  AgentConfig(
    maxSteps: 50,
    maxContextChars: 60000,
    enableTracing: true
  )

proc defaultHooks*(): RuntimeHooks =
  RuntimeHooks(
    beforeInference: nil,
    afterInference: nil,
    beforeToolCall: nil,
    afterToolCall: nil,
    onError: nil
  )

proc newAgent*(
  name: string,
  provider: LLMProvider,
  memory: MemoryHistory = nil,
  tools: ToolRegistry = nil,
  config: AgentConfig = defaultConfig(),
  hooks: RuntimeHooks = nil
): Agent =
  Agent(
    name: name,
    provider: provider,
    memory: if memory != nil: memory else: newMemoryHistory(),
    tools: if tools != nil: tools else: newToolRegistry(),
    config: config,
    hooks: if hooks != nil: hooks else: defaultHooks()
  )

proc compactContext*(agent: Agent): Future[void] {.async.} =
  ## Simple context compaction if too long
  var totalChars = 0
  for m in agent.memory.messages:
    totalChars += m.content.len
    for tc in m.toolCalls: totalChars += tc.arguments.len

  if totalChars < agent.config.maxContextChars: return

  traceInfo(agent.name, "Context too large (" & $totalChars & " characters). Starting compaction...")

  let keepCount = 12
  if agent.memory.messages.len <= keepCount + 1: return

  let toSummarize = agent.memory.messages[0 .. ^(keepCount + 1)]
  let summaryContext = @[Message(role: System, content: "Summarize very briefly the key points of this conversation for future memory.")] & toSummarize

  try:
    let summary = await agent.provider.generate(summaryContext)
    var newMessages: seq[Message] = @[]
    newMessages.add(Message(role: System, content: "[SUMMARY] " & summary.content))
    newMessages &= agent.memory.messages[^keepCount .. ^1]
    agent.memory.messages = newMessages
    traceAction(agent.name, "Compaction completed")
  except:
    traceError(agent.name, "Compaction failed: " & getCurrentExceptionMsg())

proc run*(agent: Agent, prompt: string): Future[string] {.async.} =
  ## Execute an agent cycle with the user prompt
  traceInfo("User", prompt)
  traceAgent(agent.name, "New task", prompt)

  agent.memory.addMessage(Message(role: User, content: prompt))

  var isDone = false
  var steps = 0
  var finalResponse = ""

  while not isDone and steps < agent.config.maxSteps:
    steps += 1

    if steps mod 10 == 0:
      await agent.compactContext()

    let context = agent.memory.buildContext()
    let toolsSchema = if agent.tools != nil and agent.tools.tools.len > 0: agent.tools.getToolsSchema() else: nil

    # Hook beforeInference
    if agent.hooks.beforeInference != nil:
      let shouldContinue = await agent.hooks.beforeInference(agent, context)
      if not shouldContinue:
        traceInfo(agent.name, "Inference blocked by hook")
        break

    # LLM Call
    var response: Message
    try:
      response = await agent.provider.generate(context, toolsSchema = toolsSchema)
    except CatchableError as e:
      traceError(agent.name, "LLM Error: " & e.msg)
      if agent.hooks.onError != nil:
        await agent.hooks.onError(agent, e)
      return "Error: " & e.msg

    # Hook afterInference
    if agent.hooks.afterInference != nil:
      await agent.hooks.afterInference(agent, response)

    # Trace response
    var traceContent = response.content
    for tc in response.toolCalls:
      traceContent &= "\n\nTool: " & tc.name & " Args: " & tc.arguments
    traceAgent(agent.name, "LLM Response (step " & $steps & ")", traceContent)

    if response.toolCalls.len > 0:
      # Tool calling
      agent.memory.addMessage(response)

      for tc in response.toolCalls:
        # Hook beforeToolCall
        if agent.hooks.beforeToolCall != nil:
          let shouldCall = await agent.hooks.beforeToolCall(agent, tc.name, parseJson(tc.arguments))
          if not shouldCall:
            traceInfo(agent.name, "Tool call blocked by hook: " & tc.name)
            continue

        traceAction(agent.name, "Tool call: " & tc.name)
        let result = await agent.tools.callTool(tc.name, tc.arguments)

        # Hook afterToolCall
        if agent.hooks.afterToolCall != nil:
          await agent.hooks.afterToolCall(agent, tc.name, result)

        agent.memory.addMessage(Message(
          role: Tool,
          content: result,
          toolCallId: tc.id
        ))

    else:
      # Final response
      agent.memory.addMessage(response)
      finalResponse = response.content
      isDone = true

  if steps >= agent.config.maxSteps:
    finalResponse = "[Limit reached] " & finalResponse

  traceInfo(agent.name, finalResponse)
  return finalResponse
