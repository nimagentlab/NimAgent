# Package
version       = "0.1.0"
author        = "nimagent maintainers"
description   = "A lightweight Nim SDK for building small, inspectable AI agents."
license       = "Apache-2.0"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"
requires "jsony"

# Optional: Chronos support
# requires "chronos >= 4.0.0"

task test, "Run tests":
  exec "nim c --path:src -r tests/test_messages.nim"
  exec "nim c --path:src -r tests/test_tool_registry.nim"
  exec "nim c --path:src -r tests/test_basic_memory.nim"
  exec "nim c --path:src -r tests/test_hooks.nim"

task examples, "Compile examples":
  exec "nim c --path:src -d:release examples/example_basic_chat.nim"
  exec "nim c --path:src -d:release examples/example_ollama.nim"
  exec "nim c --path:src -d:release examples/example_tool_calling.nim"
  exec "nim c --path:src -d:release examples/example_compiled_binary.nim"
  exec "nim c --path:src -d:release examples/example_runtime_hooks.nim"
