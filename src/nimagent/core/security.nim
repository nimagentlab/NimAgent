## Security Validation Layer
## =========================
## Technical action validation: path traversal detection, command injection
## detection, forbidden path blacklists, and dangerous action identification.
##
## Security levels:
##   secNone     — No active security
##   secStandard — Default security (technical validation + HITL on dangerous)
##   secCognitif — Cognitive reflection mode (LLM supervisor + HITL)
##   secAlways   — Always require manual confirmation

import std/[json, strutils, os]

type
  SecurityLevel* = enum
    secNone     ## No active security
    secStandard ## Default security
    secCognitif ## Cognitive reflection mode (LLM supervisor)
    secAlways   ## Always require manual confirmation

  ValidationResult* = object
    isValid*: bool
    reason*: string
    category*: string

  GenericValidator* = object
    forbiddenPaths*: seq[string]
    dangerousPatterns*: seq[string]

const
  DefaultForbiddenPaths* = [
    "/etc", "/boot", "/root", "/sys", "/proc",
    "/dev", "/var/log", "/var/spool/cron",
    "/usr/local/sbin", "/bin/bash", "/bin/sh",
    "C:\\Windows\\System32"
  ]

  InjectionPatterns* = [
    (";", "command separator"),
    ("&&", "and operator"),
    ("||", "or operator"),
    ("|", "pipe"),
    ("`", "backtick"),
    ("$(", "command substitution"),
    ("..", "path traversal")
  ]

proc initGenericValidator*(): GenericValidator =
  GenericValidator(
    forbiddenPaths: @DefaultForbiddenPaths,
    dangerousPatterns: @["passwd", "shadow", "sudoers", "ssh", "id_rsa"]
  )

proc containsPathTraversal*(path: string): bool =
  let norm = path.toLowerAscii()
  if norm.contains("../") or norm.contains("..\\") or
     norm.contains("%2e%2e") or norm.contains("%252e%252e"):
    return true
  try:
    let canon = normalizedPath(path)
    if canon.toLowerAscii().contains(".."):
      return true
  except:
    discard
  return false

proc detectCommandInjection*(text: string): (bool, string) =
  for (pattern, desc) in InjectionPatterns:
    if text.contains(pattern): return (true, desc)
  return (false, "")

proc isForbiddenPath*(gv: GenericValidator, path: string): bool =
  var normPath: string
  try:
    normPath = normalizedPath(path).toLowerAscii()
  except:
    normPath = path.toLowerAscii().strip(trailing = true, chars = {'/', '\\'})
  for forbidden in gv.forbiddenPaths:
    var normForbidden: string
    try:
      normForbidden = normalizedPath(forbidden).toLowerAscii()
    except:
      normForbidden = forbidden.toLowerAscii()
    if normPath.startsWith(normForbidden): return true
  for pattern in gv.dangerousPatterns:
    if normPath.contains(pattern): return true
  return false

proc validateParameters*(gv: GenericValidator,
    params: JsonNode): ValidationResult =
  ## Recursively scans JSON for paths or injections.
  result = ValidationResult(isValid: true)

  case params.kind:
  of JString:
    let val = params.getStr()
    if containsPathTraversal(val):
      return ValidationResult(isValid: false, reason: "Path traversal detected",
          category: "security")
    if gv.isForbiddenPath(val):
      return ValidationResult(isValid: false,
          reason: "Access to forbidden path", category: "security")
    let (inj, desc) = detectCommandInjection(val)
    if inj:
      return ValidationResult(isValid: false, reason: "Injection detected: " &
          desc, category: "security")
  of JObject:
    for _, v in params.pairs:
      let res = gv.validateParameters(v)
      if not res.isValid: return res
  of JArray:
    for item in params.items:
      let res = gv.validateParameters(item)
      if not res.isValid: return res
  else:
    discard

proc isDangerousAction*(toolName: string): bool =
  ## Determines whether a tool requires human validation by default.
  ## Uses exact, prefix, and suffix matching to avoid false positives
  ## (e.g. 'safe_write_file' must NOT match 'write').
  let name = toolName.toLowerAscii()
  const exactMatches = [
    "mouse_click", "mouse_drag", "mouse_scroll", "window_focus",
    "keyboard_type", "keyboard_key", "exec", "bash", "shell", "sudo",
    "click_text_on_screen", "scrape_screen_text"
  ]
  for e in exactMatches:
    if name == e: return true
  if name.startsWith("click_") or name.startsWith("drag") or
     name.startsWith("type_") or name.startsWith("write_") or
     name.startsWith("delete_") or name.startsWith("exec_") or
     name.startsWith("run_") or name.startsWith("shell_"):
    return true
  if name.endsWith("_click") or name.endsWith("_drag") or
     name.endsWith("_type") or name.endsWith("_write") or
     name.endsWith("_delete") or name.endsWith("_exec") or
     name.endsWith("_run") or name.endsWith("_shell"):
    return true
  return false
