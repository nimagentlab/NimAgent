## Workspace Tool - Safe File Operations
## Sandbox-safe file operations for agent outputs
## Safety rules per SDK spec section 3.2:
## - explicit workspace_root required
## - absolute paths rejected
## - .. traversal rejected
## - hidden files rejected by default
## - max bytes capped
## - overwrite disabled by default
## - no delete/chmod/move/rename in v0.1

import ../../utils/async_compat
import ../../utils/json_compat
import ../registry
import std/[times, os, strutils, paths]

type
  WorkspaceConfig* = object
    root*: string
    maxReadBytes*: int
    maxWriteBytes*: int
    allowOverwrite*: bool
    allowHidden*: bool
    maxDepth*: int
    maxFiles*: int

proc validateWorkspacePath*(config: WorkspaceConfig, path: string): tuple[isValid: bool, error: string] =
  ## Validates path against workspace safety rules

  # Reject absolute paths
  if isAbsolute(path):
    return (false, "Absolute paths are not allowed. Use relative paths within the workspace.")

  # Reject .. traversal
  if ".." in path:
    return (false, "Path traversal (..) is not allowed.")

  # Reject hidden files by default
  if not config.allowHidden:
    let parts = path.split({DirSep, '/'})
    for part in parts:
      if part.len > 0 and part[0] == '.':
        return (false, "Hidden files/directories are not allowed by default.")

  # Check final path is within workspace
  let fullPath = absolutePath(config.root / path)
  let workspaceRoot = absolutePath(config.root)

  if not fullPath.startsWith(workspaceRoot):
    return (false, "Path escapes workspace root.")

  return (true, "")

llmTool "List files in the workspace directory. Returns a JSON array of file entries with name, size, and modified time. Respects maxDepth and maxFiles limits.":
  proc workspaceList(
    path: string = ".",
    includeHidden: bool = false
  ): Future[string] {.async.} =
    ## List workspace files with safety constraints
    try:
      let config = WorkspaceConfig(
        root: os.getCurrentDir() / "workspace",
        maxReadBytes: 1024 * 1024,  # 1MB
        maxWriteBytes: 1024 * 1024,  # 1MB
        allowOverwrite: false,
        allowHidden: includeHidden,
        maxDepth: 3,
        maxFiles: 100
      )

      # Ensure workspace exists
      if not dirExists(config.root):
        createDir(config.root)

      let (isValid, errorMsg) = validateWorkspacePath(config, path)
      if not isValid:
        return "Error: " & errorMsg

      let fullPath = config.root / path

      if not dirExists(fullPath):
        return "Error: Directory does not exist: " & path

      var entries: seq[JsonNode] = @[]
      var fileCount = 0

      for kind, entryPath in walkDir(fullPath):
        if fileCount >= config.maxFiles:
          break

        let entryName = extractFilename(entryPath)

        # Skip hidden unless allowed
        if not config.allowHidden and entryName.len > 0 and entryName[0] == '.':
          continue

        let entry = %*{
          "name": entryName,
          "type": (if kind == pcDir: "directory" else: "file"),
          "size": (if kind == pcFile: getFileSize(entryPath) else: 0),
          "modified": (if kind == pcFile: times.format(times.local(getLastModificationTime(entryPath)), "yyyy-MM-dd HH:mm:ss") else: "")
        }

        entries.add(entry)
        fileCount += 1

      return $ %*entries
    except CatchableError as e:
      return "Error listing workspace: " & e.msg

llmTool "Read a file from the workspace. File must be within the workspace root. Respects maxReadBytes limit. Hidden files rejected by default.":
  proc workspaceRead(
    path: string,
    maxBytes: int = 1048576  # 1MB default
  ): Future[string] {.async.} =
    ## Read workspace file with safety constraints
    try:
      let config = WorkspaceConfig(
        root: os.getCurrentDir() / "workspace",
        maxReadBytes: min(maxBytes, 1024 * 1024),  # Cap at 1MB
        maxWriteBytes: 1024 * 1024,
        allowOverwrite: false,
        allowHidden: false,
        maxDepth: 3,
        maxFiles: 100
      )

      # Ensure workspace exists
      if not dirExists(config.root):
        createDir(config.root)

      let (isValid, errorMsg) = validateWorkspacePath(config, path)
      if not isValid:
        return "Error: " & errorMsg

      let fullPath = config.root / path

      if not fileExists(fullPath):
        return "Error: File does not exist: " & path

      let fileSize = getFileSize(fullPath)
      if fileSize > config.maxReadBytes:
        return "Error: File too large (" & $fileSize & " bytes). Max: " & $config.maxReadBytes & " bytes."

      let content = readFile(fullPath)
      return content
    except CatchableError as e:
      return "Error reading file: " & e.msg

llmTool "Write content to a file in the workspace. File must be within the workspace root. Overwrite disabled by default. Respects maxWriteBytes limit.":
  proc workspaceWrite(
    path: string,
    content: string,
    allowOverwrite: bool = false
  ): Future[string] {.async.} =
    ## Write workspace file with safety constraints
    try:
      let config = WorkspaceConfig(
        root: os.getCurrentDir() / "workspace",
        maxReadBytes: 1024 * 1024,
        maxWriteBytes: 1024 * 1024,
        allowOverwrite: allowOverwrite,
        allowHidden: false,
        maxDepth: 3,
        maxFiles: 100
      )

      # Check content size
      if content.len > config.maxWriteBytes:
        return "Error: Content too large (" & $content.len & " bytes). Max: " & $config.maxWriteBytes & " bytes."

      # Ensure workspace exists
      if not dirExists(config.root):
        createDir(config.root)

      let (isValid, errorMsg) = validateWorkspacePath(config, path)
      if not isValid:
        return "Error: " & errorMsg

      let fullPath = config.root / path
      let parent = parentDir(fullPath)

      # Ensure parent directory is within workspace
      if parent != config.root:
        let parentRel = relativePath(parent, config.root)
        let (parentValid, parentError) = validateWorkspacePath(config, parentRel)
        if not parentValid:
          return "Error: Invalid parent directory: " & parentError

      # Check overwrite
      if fileExists(fullPath) and not config.allowOverwrite:
        return "Error: File already exists and overwrite is disabled. Use allowOverwrite=true to replace."

      # Create parent directories if needed
      if not dirExists(parent):
        createDir(parent)

      writeFile(fullPath, content)
      return "Successfully wrote " & $content.len & " bytes to " & path
    except CatchableError as e:
      return "Error writing file: " & e.msg
