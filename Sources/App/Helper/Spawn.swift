import Foundation


enum SpawnError: Error {
    case commandFailed(cmd: String, returnCode: Int32, args: [String]?)
    case executableDoesNotExist(cmd: String)
}

public extension Process {
    /// Get the absolute path of an executable
    static func findExecutable(cmd: String) throws -> String {
        var command: String
        if !cmd.hasPrefix("/") {
            command = (try? spawnWithOutput(cmd: "/usr/bin/which", args: [cmd]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)) ?? ""
        } else {
            command = cmd
        }
        if cmd == "cdo" && command == "" && FileManager.default.fileExists(atPath: "/opt/homebrew/bin/cdo") {
            // workaround for mac because cdo is not in PATH
            if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/cdo") {
                command = "/opt/homebrew/bin/cdo"
            }
            if FileManager.default.fileExists(atPath: "/usr/local/bin/cdo") {
                command = "/usr/local/bin/cdo"
            }
        }
        guard FileManager.default.fileExists(atPath: command) else {
            throw SpawnError.executableDoesNotExist(cmd: command)
        }
        return command
    }
    
    /// Spawn a Process with optional attached pipes
    static func spawn(cmd: String, args: [String]?, stdout: Pipe? = nil, stderr: Pipe? = nil) throws -> Process {
        let proc = Process()
        let command = try findExecutable(cmd: cmd)

        proc.executableURL = URL(fileURLWithPath: command)
        proc.arguments = args

        if let pipe = stdout {
            proc.standardOutput = pipe
        }
        if let pipe = stderr {
            proc.standardError = pipe
        }
        /// somehow this crashes from time to time with a bad file descriptor
        do {
            try proc.run()
        } catch {
            print("command failed, retry")
            try! proc.run()
        }
        return proc
    }

    static func spawnOrDie(cmd: String, args: [String]?) throws {
        let task = try Process.spawn(cmd: cmd, args: args)
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw SpawnError.commandFailed(cmd: cmd, returnCode: task.terminationStatus, args: args)
        }
    }

    static func spawnWithOutput(cmd: String, args: [String]?) throws -> String {
        let pipe = Pipe()
        let eerror = Pipe()
        let task = try Process.spawn(cmd: cmd, args: args, stdout: pipe, stderr: eerror)
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw SpawnError.commandFailed(cmd: cmd, returnCode: task.terminationStatus, args: args)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: String.Encoding.utf8)!
    }
}
