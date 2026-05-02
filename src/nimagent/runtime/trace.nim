## Simplified tracing module for nimagent
## Handles console display without complex persistence

import std/[terminal, times]

type LogLevel* = enum
  lvlDebug, lvlInfo, lvlAction, lvlAgent, lvlError

var minLogLevel* = lvlInfo

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

  styledEcho fgBlack, styleDim, timeStr, " ", color, styleBright, prefix, " [", agentName, "] ", fgDefault, message

# Simplified public API
proc traceDebug*(agentName, message: string) = logMessage(lvlDebug, agentName, message)
proc traceInfo*(agentName, message: string) = logMessage(lvlInfo, agentName, message)
proc traceAction*(agentName, message: string) = logMessage(lvlAction, agentName, message)
proc traceAgent*(agentName, title, content: string) = logMessage(lvlAgent, agentName, title & ": " & content)
proc traceError*(agentName, message: string) = logMessage(lvlError, agentName, message)
