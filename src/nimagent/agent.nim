## nimagent - Unified Agent
## ========================
## The most capable ReAct agent engine for compiled LLM agents.
## Merges the public SDK agent with the DeepAgent engine into one.
##
## Features:
## - ReAct loop with tool calling
## - Runtime hooks (beforeInference, afterInference, beforeToolCall, afterToolCall, onError)
## - Automatic context compaction when context grows too large
## - Skill injection from SkillManager
## - Memory persistence and sliding window context management
## - Runtime tracing with multiple output targets (console + file)
## - Configurable limits (maxSteps, maxContextChars, enableTracing)

import ./utils/async_compat
import ./utils/json_compat
import ./messages
import ./providers/base
import ./memory/basic_memory
import ./tools/registry
import ./runtime/trace
import ./skills/skill_manager
import ./core/security
import std/[tables, strutils]

export messages, base, basic_memory, registry

type
  AgentModality* = enum
    modText           ## Bilateral Text-to-Text (default)
    modVision         ## Bilateral Vision-to-Text & Text-to-Image
    modSound          ## Bilateral Sound-to-Text & Text-to-Sound
    modSoundToSound   ## Specialized pure audio
    modVisionToVision ## Specialized pure video

  AgentConfig* = object
    maxSteps*: int
    maxContextTokens*: int ## If 0, auto-queries provider. Replaced maxContextChars.
    enableTracing*: bool
    compactEvery*: int    ## Compact context every N steps (0 = disabled)
    systemPrompt*: string ## Default system prompt
    model*: string        ## Default model name
    heartbeatMs*: int     ## Interval for background check (0 = disabled)
    autoSaveMemory*: bool ## Automatically save memory to disk after each run
    autoSavePath*: string ## Path for auto-saving memory

  RuntimeHooks* = ref object
    beforeInference*: proc(agent: Agent, messages: seq[Message]): Future[bool] {.async.}
    afterInference*: proc(agent: Agent, response: Message): Future[void] {.async.}
    beforeToolCall*: proc(agent: Agent, toolName: string,
        args: JsonNode): Future[bool] {.async.}
    afterToolCall*: proc(agent: Agent, toolName: string,
        result: string): Future[void] {.async.}
    onError*: proc(agent: Agent, error: ref Exception): Future[void] {.async.}
    onCycleEnd*: proc(agent: Agent, step: int, response: string): Future[void] {.async.}

  ConfigFeature* = enum
    cfgSecurity, ## Permet de modifier le SecurityLevel (secNone, secStandard, etc.)
    cfgModel,    ## Allows changing the target model (gpt-4o, etc.)
    cfgVision,   ## Allows enabling/disabling vision
    cfgProvider, ## Permet de changer la BaseURL ou l'API Key
    cfgHeartbeat ## Permet de modifier l'intervalle de heartbeat

  Agent* = ref object
    name*: string
    config*: AgentConfig
    provider*: LLMProvider
    memory*: MemoryHistory
    tools*: ToolRegistry
    hooks*: RuntimeHooks
    skills*: SkillManager
    modalities*: set[AgentModality]
    securityLevel*: SecurityLevel
    toolSecurity*: Table[string, SecurityLevel]
    allowedRuntimeConfigs*: set[ConfigFeature] ## Post-compilation granularity
    forceJson*: bool

proc defaultConfig*(): AgentConfig =
  AgentConfig(
    maxSteps: 10,
    maxContextTokens: 0, ## 0 means auto-discover
    enableTracing: true,
    compactEvery: 10,
    systemPrompt: "You are a helpful AI assistant.",
    model: "gpt-4o-mini",
    heartbeatMs: 0, # Disabled by default
    autoSaveMemory: false,
    autoSavePath: "agent_memory.json"
  )

proc defaultHooks*(): RuntimeHooks =
  RuntimeHooks(
    beforeInference: nil,
    afterInference: nil,
    beforeToolCall: nil,
    afterToolCall: nil,
    onError: nil,
    onCycleEnd: nil
  )

proc newAgent*(
  name: string,
  provider: LLMProvider,
  memory: MemoryHistory = nil,
  tools: ToolRegistry = nil,
  config: AgentConfig = defaultConfig(),
  hooks: RuntimeHooks = nil,
  skills: SkillManager = nil,
  forceJson: bool = false,
  autoSave: bool = false
): Agent =
  ## Creates a new Agent with full configuration.
  ## If autoSave is true, it automatically loads and saves memory to <name>_memory.json.
  var finalConfig = config
  if autoSave:
    finalConfig.autoSaveMemory = true
    if finalConfig.autoSavePath == "agent_memory.json":
      finalConfig.autoSavePath = name & "_memory.json"

  let mem = if memory != nil:
              memory
            elif finalConfig.autoSaveMemory:
              let loaded = loadHistoryFromDisk(finalConfig.autoSavePath)
              loaded.systemPrompt = finalConfig.systemPrompt
              loaded
            else:
              newMemoryHistory(finalConfig.systemPrompt)

  let sk = if skills != nil: skills else: newSkillManager()
  sk.loadSkills() # cache skills at startup, avoids disk I/O in the hot loop

  Agent(
    name: name,
    provider: provider,
    memory: mem,
    tools: if tools != nil: tools else: newToolRegistry(),
    config: finalConfig,
    hooks: if hooks != nil: hooks else: defaultHooks(),
    skills: sk,
    forceJson: forceJson,
    modalities: {modText},
    securityLevel: secNone,
    toolSecurity: initTable[string, SecurityLevel]()
  )

proc applyRuntimeConfig*(agent: Agent, config: JsonNode) =
  ## Dynamically applies configuration ONLY for authorized features.

  if config.hasKey("securityLevel") and cfgSecurity in
      agent.allowedRuntimeConfigs:
    let levelStr = config["securityLevel"].getStr()
    agent.securityLevel = case levelStr:
      of "secNone": secNone
      of "secStandard": secStandard
      of "secCognitif": secCognitif
      of "secAlways": secAlways
      else: agent.securityLevel
    echo "⚙️ [CONFIG] Security level updated: ",
        $agent.securityLevel
  elif config.hasKey("securityLevel"):
    echo "⚠️ [CONFIG] Security change IGNORED (Feature locked at compile time)"

  if config.hasKey("enableVision") and cfgVision in agent.allowedRuntimeConfigs:
    let vision = config["enableVision"].getBool()
    if vision: agent.modalities.incl(modVision)
    else: agent.modalities.excl(modVision)
    echo "⚙️ [CONFIG] Vision modality updated."
  elif config.hasKey("enableVision"):
    echo "⚠️ [CONFIG] Vision change IGNORED (Feature locked)"

  if config.hasKey("model") and cfgModel in agent.allowedRuntimeConfigs:
    let newModel = config["model"].getStr()
    agent.config.model = newModel
    # On essaie de mettre à jour le provider si possible
    if not agent.provider.isNil:
      agent.provider.setModel(newModel)
    echo "⚙️ [CONFIG] LLM model updated: ", agent.config.model
  elif config.hasKey("model"):
    echo "⚠️ [CONFIG] Model change IGNORED (Feature locked)"

  if config.hasKey("heartbeatMs") and cfgHeartbeat in agent.allowedRuntimeConfigs:
    agent.config.heartbeatMs = config["heartbeatMs"].getInt()
    echo "⚙️ [CONFIG] Heartbeat updated: ", agent.config.heartbeatMs, "ms"
  elif config.hasKey("heartbeatMs"):
    echo "⚠️ [CONFIG] Heartbeat change IGNORED (Feature locked)"

  if config.hasKey("provider") and cfgProvider in agent.allowedRuntimeConfigs:
    let providerConfig = config["provider"]
    if providerConfig.hasKey("baseUrl"):
      let url = providerConfig["baseUrl"].getStr()
      agent.provider.setBaseUrl(url)
      echo "⚙️ [CONFIG] Provider baseUrl updated: ", url
    if providerConfig.hasKey("apiKey"):
      let key = providerConfig["apiKey"].getStr()
      agent.provider.setApiKey(key)
      echo "⚙️ [CONFIG] Provider apiKey updated."
    if providerConfig.hasKey("model"):
      let model = providerConfig["model"].getStr()
      agent.provider.setModel(model)
      agent.config.model = model
      echo "⚙️ [CONFIG] Provider model updated: ", model
  elif config.hasKey("provider"):
    echo "⚠️ [CONFIG] Provider modification IGNORED (Feature locked at compilation)"

proc setSystemPrompt*(agent: Agent, prompt: string) =
  ## Updates the agent's system prompt.
  agent.memory.systemPrompt = prompt
  agent.config.systemPrompt = prompt

proc compactContext*(agent: Agent): Future[void] {.async.} =
  ## Context compaction: summarizes old messages when context grows too large.
  ## Keeps the latest `keepCount` messages intact and summarizes the rest.
  var totalTokens = 0
  for m in agent.memory.messages:
    totalTokens += agent.provider.countTokens(m.content)
    for tc in m.toolCalls:
      totalTokens += agent.provider.countTokens(tc.name) # Compter aussi le nom
      totalTokens += agent.provider.countTokens(tc.arguments)

  var limit = agent.config.maxContextTokens
  if limit <= 0:
    # Query the provider dynamically and cache the result
    limit = await agent.provider.getMaxContextTokens()
    agent.config.maxContextTokens = limit

  # We compress when we reach 80% of the model's actual capacity
  let threshold = int(float(limit) * 0.8)

  if totalTokens < threshold:
    return

  traceInfo(agent.name, "Context near limit (" & $totalTokens & "/" & $limit & " tokens). Starting compaction...")

  var actualKeepCount = 12
  if agent.memory.messages.len <= actualKeepCount + 1:
    return

  # Adjust actualKeepCount to avoid breaking Assistant -> Tool call chains
  while actualKeepCount < agent.memory.messages.len:
    let oldestKept = agent.memory.messages[^actualKeepCount]
    if oldestKept.role == Tool:
      actualKeepCount += 1
    elif oldestKept.role == Assistant and oldestKept.toolCalls.len > 0:
      break
    else:
      break

  if agent.memory.messages.len <= actualKeepCount + 1:
    return

  let toSummarize = agent.memory.messages[0 .. ^(actualKeepCount + 1)]
  let summaryContext = @[Message(role: System,
      content: "Summarize very briefly the key points of this conversation for future memory.")] & toSummarize

  try:
    let summary = await agent.provider.generate(summaryContext)
    var newMessages: seq[Message] = @[]
    newMessages.add(Message(role: System, content: "[SUMMARY] " &
        summary.content))
    newMessages &= agent.memory.messages[^actualKeepCount .. ^1]
    agent.memory.messages = newMessages
    traceAction(agent.name, "Compaction completed")
  except:
    traceError(agent.name, "Compaction failed: " & getCurrentExceptionMsg())

proc run*(agent: Agent, prompt: string): Future[string] {.async.} =
  ## Execute a full agent cycle (ReAct loop).
  ## 1. Add user message to memory
  ## 2. Loop: build context → LLM inference → tool calls or final response
  ## 3. Compact context periodically
  ## 4. Return final text response
  traceInfo("User", prompt)
  traceAgent(agent.name, "New task", prompt)

  # Inject active skills into context (already cached at agent creation)
  let skillPrompt = agent.skills.getSkillPrompt()

  # Add user message
  agent.memory.addMessage(Message(role: User, content: prompt))

  var isDone = false
  var steps = 0
  var finalResponse = ""

  while not isDone and (agent.config.maxSteps <= 0 or steps <
      agent.config.maxSteps):
    steps += 1

    # Periodic compaction
    if agent.config.compactEvery > 0 and steps mod agent.config.compactEvery == 0:
      await agent.compactContext()

    let context = agent.memory.buildContext(ragContext = skillPrompt)
    let toolsSchema = if agent.tools != nil and agent.tools.tools.len > 0:
                        agent.tools.getToolsSchema()
                      else:
                        nil

    # Hook: beforeInference
    if agent.hooks.beforeInference != nil:
      let shouldContinue = await agent.hooks.beforeInference(agent, context)
      if not shouldContinue:
        traceInfo(agent.name, "Inference blocked by hook")
        break

    # LLM Call
    var response: Message
    try:
      response = await agent.provider.generate(
        context,
        toolsSchema = toolsSchema,
        forceJson = agent.forceJson
      )
    except CatchableError as e:
      traceError(agent.name, "LLM Error: " & e.msg)
      if agent.hooks.onError != nil:
        await agent.hooks.onError(agent, e)
      return "Error: " & e.msg

    # Hook: afterInference
    if agent.hooks.afterInference != nil:
      await agent.hooks.afterInference(agent, response)

    # Trace response
    var traceContent = response.content
    for tc in response.toolCalls:
      traceContent &= "\n\nTool: " & tc.name & " Args: " & tc.arguments
    traceAgent(agent.name, "LLM Response (step " & $steps & ")", traceContent)

    if response.toolCalls.len > 0:
      # Tool calling phase
      agent.memory.addMessage(response)

      for tc in response.toolCalls:
        # Hook: beforeToolCall
        if agent.hooks.beforeToolCall != nil:
          var argsNode = newJObject()
          try:
            if tc.arguments.len > 0:
              argsNode = parseJson(tc.arguments)
          except Exception as e:
            traceError(agent.name, "Invalid tool JSON from LLM: " & e.msg)

          let shouldCall = await agent.hooks.beforeToolCall(agent, tc.name, argsNode)
          if not shouldCall:
            traceInfo(agent.name, "Tool call blocked by hook: " & tc.name)
            continue

        traceAction(agent.name, "Tool call: " & tc.name)
        let result = await agent.tools.callTool(tc.name, tc.arguments)

        # Hook: afterToolCall
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

    # Hook: onCycleEnd
    if agent.hooks.onCycleEnd != nil:
      await agent.hooks.onCycleEnd(agent, steps, finalResponse)

  if agent.config.maxSteps > 0 and steps >= agent.config.maxSteps:
    finalResponse = "[Limit reached after " & $steps & " steps] " & finalResponse

  if agent.config.autoSaveMemory:
    agent.memory.saveToDisk(agent.config.autoSavePath)

  traceInfo(agent.name, finalResponse)
  return finalResponse

proc chat*(agent: Agent, prompt: string): Future[string] {.async.} =
  ## Alias for `run` — conversational interface.
  return await agent.run(prompt)

proc chatLoop*(agent: Agent) {.async.} =
  ## Starts an interactive CLI loop with the user.
  echo "--- " & agent.name & " est en ligne. Tape 'quit' ou 'exit' pour quitter. ---"
  while true:
    stdout.write("\nUser : ")
    let userInput = stdin.readLine()
    if userInput.strip().toLowerAscii() in ["quit", "exit"]:
      echo "Déconnexion."
      break

    let response = await agent.chat(userInput)
    echo "\n" & agent.name & " : ", response
