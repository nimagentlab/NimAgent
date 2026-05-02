## Runtime Hooks for nimagent
## Extension points for instrumenting the agent cycle

## Note: RuntimeHooks types are defined in agent.nim to avoid
## circular references. This file is kept for compatibility.

import std/asyncdispatch

## Hooks are defined in agent.nim with the complete Agent type
## Import agent.nim to use RuntimeHooks
