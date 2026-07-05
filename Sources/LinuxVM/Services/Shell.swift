import Foundation

/// Runs command-line tools. A GUI app launched from /Applications inherits a
/// minimal PATH (no Homebrew), so tools are located by absolute path.
enum Shell {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        var ok: Bool { status == 0 }
    }

    /// Runs `tool` with `args`, optionally feeding `stdin`. Synchronous.
    @discardableResult
    static func run(_ tool: String, _ args: [String],
                    stdin: String? = nil, timeout: TimeInterval = 0) -> Result {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tool)
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        let inPipe = Pipe()
        if stdin != nil { proc.standardInput = inPipe }

        do { try proc.run() } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        if let stdin, let data = stdin.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
            try? inPipe.fileHandleForWriting.close()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return Result(status: proc.terminationStatus,
                      stdout: String(data: outData, encoding: .utf8) ?? "",
                      stderr: String(data: errData, encoding: .utf8) ?? "")
    }

    // Built-in macOS tools (always present).
    static let hdiutil = "/usr/bin/hdiutil"
    static let sshKeygen = "/usr/bin/ssh-keygen"
    static let ssh = "/usr/bin/ssh"
    static let arp = "/usr/sbin/arp"
    static let ping = "/sbin/ping"

    /// qemu-img is optional (Homebrew). Returns the first that exists.
    static var qemuImg: String? {
        ["/opt/homebrew/bin/qemu-img", "/usr/local/bin/qemu-img"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
    static var hasQemuImg: Bool { qemuImg != nil }
}
