## Tool Permissions Module
## Defines permission flags for tools in the public SDK

import std/json

type
  ToolPermission* = enum
    ## Permission flags for tool safety classification
    tpSafe           ## Tool is safe to run without confirmation
    tpDangerous      ## Tool could cause harm (delete, execute, etc.)
    tpRequiresConfirmation  ## Tool requires explicit user confirmation
    tpWorkspaceOnly  ## Tool is restricted to workspace directory
    tpNoNetwork      ## Tool does not make network requests
    tpReadOnly       ## Tool only reads, never writes
    tpWriteOnly      ## Tool only writes, never reads

  ToolPermissions* = set[ToolPermission]

proc toJson*(perms: ToolPermissions): JsonNode =
  ## Convert permissions set to JSON array
  var arr = newJArray()
  if tpDangerous in perms:
    arr.add(%"dangerous")
  if tpRequiresConfirmation in perms:
    arr.add(%"requires_confirmation")
  if tpWorkspaceOnly in perms:
    arr.add(%"workspace_only")
  if tpNoNetwork in perms:
    arr.add(%"no_network")
  if tpReadOnly in perms:
    arr.add(%"read_only")
  if tpWriteOnly in perms:
    arr.add(%"write_only")
  return arr

proc defaultSafePermissions*(): ToolPermissions =
  ## Default safe permissions (read-only, workspace-only, no network)
  return {tpSafe, tpWorkspaceOnly, tpNoNetwork, tpReadOnly}

proc defaultWritePermissions*(): ToolPermissions =
  ## Permissions for write operations (workspace-only, requires confirmation)
  return {tpWorkspaceOnly, tpNoNetwork, tpRequiresConfirmation}

proc isDangerous*(perms: ToolPermissions): bool =
  ## Check if tool is marked as dangerous
  return tpDangerous in perms

proc requiresConfirmation*(perms: ToolPermissions): bool =
  ## Check if tool requires user confirmation
  return tpRequiresConfirmation in perms or tpDangerous in perms

proc isWorkspaceOnly*(perms: ToolPermissions): bool =
  ## Check if tool is restricted to workspace
  return tpWorkspaceOnly in perms
