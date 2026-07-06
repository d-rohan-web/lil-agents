import Foundation

/// Generic session handler for local LLMs (Llama, Ollama, vLLM)
class LocalLLMSession: NSObject, AgentSession {
    var isRunning: Bool = false
    var isBusy: Bool = false
    var history: [AgentMessage] = []

    var onText: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onToolUse: ((String, [String: Any]) -> Void)?
    var onToolResult: ((String, Bool) -> Void)?
    var onSessionReady: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onProcessExit: (() -> Void)?

    private var config: LocalLLMConfig
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var readThread: Thread?
    private let queue = DispatchQueue(label: "com.lil-agents.localllm", attributes: .concurrent)

    init(provider: AgentProvider) {
        super.init()
        self.config = LocalLLMConfig.load(for: provider)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        switch config.provider {
        case .localOllama:
            startOllama()
        case .localVllm:
            startVLLM()
        case .localLlama:
            startLlama()
        default:
            onError?("Unknown local LLM provider")
        }
    }

    private func startOllama() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "ollama", fallbackPaths: [
            "\(home)/.local/bin/ollama",
            "/usr/local/bin/ollama",
            "/opt/homebrew/bin/ollama",
            "/opt/ollama/bin/ollama"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                self?.onError?("Ollama not found. \(AgentProvider.localOllama.installInstructions)")
                self?.isRunning = false
                return
            }
            self.launchOllamaProcess(binaryPath: binaryPath)
        }
    }

    private func startVLLM() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "vllm", fallbackPaths: [
            "\(home)/.venv/bin/vllm",
            "/usr/local/bin/vllm",
            "\(home)/.local/bin/vllm"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                self?.onError?("vLLM not found. \(AgentProvider.localVllm.installInstructions)")
                self?.isRunning = false
                return
            }
            self.launchVLLMProcess(binaryPath: binaryPath)
        }
    }

    private func startLlama() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        ShellEnvironment.findBinary(name: "llama", fallbackPaths: [
            "\(home)/.local/bin/llama",
            "/usr/local/bin/llama",
            "/opt/homebrew/bin/llama"
        ]) { [weak self] path in
            guard let self = self, let binaryPath = path else {
                self?.onError?("Llama not found. \(AgentProvider.localLlama.installInstructions)")
                self?.isRunning = false
                return
            }
            self.launchLlamaProcess(binaryPath: binaryPath)
        }
    }

    private func launchOllamaProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "run",
            config.modelName,
            "--verbose"
        ]

        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        do {
            try proc.run()
            self.process = proc
            onSessionReady?()
            readOutputAsync()
        } catch {
            onError?("Failed to start Ollama: \(error.localizedDescription)")
            isRunning = false
        }
    }

    private func launchVLLMProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = [
            "--model", config.modelName,
            "--port", "8000",
            "--tensor-parallel-size", "1"
        ]

        outputPipe = Pipe()
        errorPipe = Pipe()
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        do {
            try proc.run()
            self.process = proc
            // Give vLLM time to start the server
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.onSessionReady?()
            }
            readOutputAsync()
        } catch {
            onError?("Failed to start vLLM: \(error.localizedDescription)")
            isRunning = false
        }
    }

    private func launchLlamaProcess(binaryPath: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = ["-i", "-c", "2048"]

        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()

        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errorPipe

        do {
            try proc.run()
            self.process = proc
            onSessionReady?()
            readOutputAsync()
        } catch {
            onError?("Failed to start Llama: \(error.localizedDescription)")
            isRunning = false
        }
    }

    func send(message: String) {
        guard let proc = process, proc.isRunning, let stdin = inputPipe?.fileHandleForWriting else {
            onError?("LLM process not running")
            return
        }

        isBusy = true
        history.append(AgentMessage(role: .user, text: message))

        if let data = (message + "\n").data(using: .utf8) {
            stdin.write(data)
        }
    }

    func terminate() {
        process?.terminate()
        inputPipe?.fileHandleForWriting.closeFile()
        isRunning = false
        onProcessExit?()
    }

    private func readOutputAsync() {
        readThread = Thread { [weak self] in
            guard let self = self, let pipe = self.outputPipe else { return }
            while self.isRunning {
                let data = pipe.fileHandleForReading.availableData
                if data.isEmpty {
                    usleep(100000) // 100ms
                    continue
                }
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    DispatchQueue.main.async {
                        self.onText?(output)
                    }
                }
            }
        }
        readThread?.start()
    }
}
