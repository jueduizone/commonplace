import Foundation

/// A conservative admission estimate, not a measured peak or a promise against jetsam.
/// Actual peaks depend on the model, context, runtime and device; see the release checklist.
struct ModelCandidate: Equatable, Sendable {
    let id: String
    let file: String
    let bytes: UInt64

    var supported: Bool {
        let name = URL(fileURLWithPath: file).lastPathComponent.lowercased()
        return name.hasSuffix(".gguf") && (name.contains("minicpm5-2b") || name.contains("gemma-4-e2b"))
    }

    var estimatedPeak: UInt64 { bytes.addingReportingOverflow(1_073_741_824).overflow ? .max : bytes + 1_073_741_824 }
}

enum ModelPolicy {
    /// Reads the current process's available memory, supplied by os_proc_available_memory.
    /// Ling is deliberately excluded until its separate physical-device validation is complete.
    static func select(_ candidates: [ModelCandidate], available: UInt64, preferred: String?) -> ModelCandidate? {
        let fitting = candidates.filter { $0.supported && $0.estimatedPeak < available }
        if let preferred { return fitting.first { $0.id == preferred } }
        return fitting.sorted { ($0.estimatedPeak, $0.id) < ($1.estimatedPeak, $1.id) }.first
    }
}
