import Foundation

/// Append-only trace file in Caches (DEBUG only) — used when the unified log is unavailable.
enum DebugTrace {
    static func log(_ message: @autoclosure () -> String) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "trace.log")
        let line = "\(Date.now.formatted(date: .omitted, time: .standard)) \(message())\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}
