## Tests for LLM providers

import std/[asyncdispatch, json, unittest, options]
import nimagent
import nimagent/providers/base

suite "Providers":
  test "Base LLMProvider type":
    # Checks that LLMProvider is a ref object of RootObj
    # and can be inherited
    type
      TestProvider = ref object of LLMProvider
        dummy: string

    let tp = TestProvider(dummy: "test")
    check tp.dummy == "test"

  test "Messages construction":
    let msg = Message(
      role: User,
      content: "Test message",
      toolCallId: "",
      toolCalls: @[]
    )
    check msg.role == User
    check msg.content == "Test message"

  test "ToolCall creation":
    let tc = ToolCall(
      id: "call_abc123",
      name: "read_file",
      arguments: "{\"path\": \"/tmp/test.txt\"}"
    )
    check tc.id == "call_abc123"
    check tc.name == "read_file"
    check tc.arguments == "{\"path\": \"/tmp/test.txt\"}"

  test "Ollama provider configuration":
    let provider = newOllamaProvider(
      baseUrl = "http://localhost:11434",
      model = "llama3.2"
    )
    check provider.baseUrl == "http://localhost:11434"
    check provider.model == "llama3.2"
    check provider.temperature == 0.7
    check provider.maxRetries == 3

  test "Ollama provider with custom model":
    let provider = newOllamaProvider(
      baseUrl = "http://localhost:11434",
      model = "mistral",
      temperature = 0.5
    )
    check provider.model == "mistral"
    check provider.baseUrl == "http://localhost:11434"

  test "OpenAI provider configuration":
    let provider = newOpenAIProvider(
      apiKey = "test-openai-key",
      model = "gpt-4o-mini"
    )
    check provider.model == "gpt-4o-mini"
    check provider.apiKey == "test-openai-key"

  test "Anthropic provider configuration":
    let provider = newAnthropicProvider(
      apiKey = "test-anthropic-key",
      model = "claude-3-haiku"
    )
    check provider.model == "claude-3-haiku"
    check provider.apiKey == "test-anthropic-key"

  test "Provider inheritance check":
    # Checks that all providers inherit from LLMProvider
    let ollama = newOllamaProvider()
    let openai = newOpenAIProvider(apiKey = "test")
    let anthropic = newAnthropicProvider(apiKey = "test")

    # These assignments would fail to compile if inheritance was incorrect
    discard ollama of LLMProvider
    discard openai of LLMProvider
    discard anthropic of LLMProvider
