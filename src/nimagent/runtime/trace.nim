## nimagent - Runtime Tracing & Logging
## Unified tracing module with console display and file persistence.
## Single source of truth for all logging in the framework.

import std/[terminal, times, os]

type LogLevel* = enum
  lvlDebug, lvlInfo, lvlAction, lvlAgent, lvlError

var minLogLevel* = lvlInfo
var logDirectory* = "logs"
var enableFileLog* = true
var sessionLogFile*: string = ""

proc initLogger*(dir: string = "logs", fileLog: bool = true) =
  ## Initializes the logging system.
  ## Creates a `logs/` directory and a unique session file.
  logDirectory = dir
  enableFileLog = fileLog
  if enableFileLog:
    createDir(logDirectory)
    let timeStr = now().format("yyyy-MM-dd") & "_" & now().format("HH-mm-ss")
    sessionLogFile = logDirectory / "session_" & timeStr & ".log"

proc setLogLevel*(level: LogLevel) =
  minLogLevel = level

proc logMessage*(level: LogLevel, agentName, message: string) =
  if level < minLogLevel: return

  let timeStr = now().format("HH:mm:ss")

  var prefix = ""
  var color = fgWhite

  case level:
    of lvlDebug:
      prefix = "[DEBUG]"
      color = fgBlue
    of lvlInfo:
      prefix = "[INFO]"
      color = fgCyan
    of lvlAction:
      prefix = "[ACTION]"
      color = fgMagenta
    of lvlAgent:
      prefix = "[AGENT]"
      color = fgYellow
    of lvlError:
      prefix = "[ERROR]"
      color = fgRed

  # Console output
  styledEcho fgBlack, styleDim, timeStr, " ", color, styleBright, prefix,
    " [", agentName, "] ", fgDefault, message

  # File logging
  if enableFileLog:
    if sessionLogFile == "":
      initLogger()
    let plainLog = timeStr & " " & prefix & " [" & agentName & "] " & message & "\n"
    let f = open(sessionLogFile, fmAppend)
    f.write(plainLog)
    f.close()

# ── Public API (short aliases) ──

proc traceDebug*(agentName, message: string) = logMessage(lvlDebug, agentName, message)
proc traceInfo*(agentName, message: string) = logMessage(lvlInfo, agentName, message)
proc traceAction*(agentName, message: string) = logMessage(lvlAction, agentName, message)
proc traceAgent*(agentName, title, content: string) = logMessage(lvlAgent, agentName, title & ": " & content)
proc traceError*(agentName, message: string) = logMessage(lvlError, agentName, message)

# ── Agent-specific trace files (for debugging prompts/JSON) ──

proc traceAgentToFile*(agentName: string, title: string, content: string) =
  ## Creates a separate trace file for a specific agent.
  if not enableFileLog: return
  if sessionLogFile == "":
    initLogger()

  let traceFile = logDirectory / agentName & "_trace.md"
  let f = open(traceFile, fmAppend)
  let timeStr = now().format("HH:mm:ss")
  f.write("### " & timeStr & " - " & title & "\n")
  f.write(content & "\n\n---\n\n")
  f.close()