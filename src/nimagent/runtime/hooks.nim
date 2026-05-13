## nimagent - Runtime Hooks
## Extension points for instrumenting the agent cycle.
##
## NOTE: RuntimeHooks types are defined in agent.nim (to avoid circular refs).
## This file re-exports them for convenient `import nimagent/runtime/hooks`.

import ../agent
export Agent, RuntimeHooks