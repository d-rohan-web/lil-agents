# Contributing to lil-agents

Thanks for interest in contributing! Here's how to get started.

## Local LLM Support

This project now supports multiple local LLM backends:

### Supported Local LLMs

- **Ollama** - Easiest to use, pre-quantized models
  ```bash
  brew install ollama
  ollama serve
  ```

- **vLLM** - High-performance inference server
  ```bash
  python3 -m venv ~/.venv
  source ~/.venv/bin/activate
  pip install vllm
  python -m vllm.entrypoints.openai.api_server
  ```

- **Llama.cpp** - Lightweight C++ implementation
  ```bash
  brew install llama.cpp
  llama-cli -m <path-to-model.gguf> -i
  ```

### Adding a New Local LLM

1. Add a new case to `AgentProvider` enum in `AgentSession.swift`:
   ```swift
   case localMyLLM
   ```

2. Update the properties (displayName, binaryName, etc.)

3. Add configuration logic in `LocalLLMConfig`

4. Create or update the session handler in `LocalLLMSession.swift`

5. Test detection with `AgentProvider.detectAvailableProviders()`

## Building

```bash
open lil-agents.xcodeproj
```

Build with Xcode or `xcodebuild`.

## Testing

1. Install a local LLM (Ollama recommended for testing)
2. Run the app and select it from the Provider menu
3. Test interactive chat

## Code Style

- Follow Swift naming conventions
- Use descriptive variable names
- Add comments for complex logic

## Submitting Changes

1. Fork the repo
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes
4. Push and open a PR
