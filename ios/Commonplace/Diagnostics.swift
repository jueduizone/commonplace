import Foundation
import Darwin
import UIKit

struct DeviceSnapshot: Codable, Sendable {
    var date: String
    var device: String
    var os: String
    var build: String
    var phase: String
    var availableBytes: UInt64
    var physicalFootprintBytes: UInt64
    var residentBytes: UInt64
    var thermalState: Int
    var model: String
    var mmap: Bool
    var background: String

    @MainActor static func capture(build: String, phase: String, model: String, mmap: Bool, background: String) -> Self {
        var name = utsname(); uname(&name)
        let device = withUnsafeBytes(of: &name.machine) { bytes in String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self)) }
        return .init(date: ISO8601DateFormatter().string(from: Date()), device: device,
                     os: UIDevice.current.systemVersion, build: build, phase: phase,
                     availableBytes: CPAvailableMemory(), physicalFootprintBytes: CPPhysicalFootprint(), residentBytes: CPResidentMemory(),
                     thermalState: ProcessInfo.processInfo.thermalState.rawValue, model: model, mmap: mmap, background: background)
    }
}

struct EvalQuestion: Decodable, Sendable {
    struct History: Decodable, Sendable { var query: String; var answer: String }
    var id: String
    var query: String
    var history: [History]?
}

/// Streaming, bounded reads for the Files probe: map the file in place and touch at most 64 MiB.
/// It deliberately does not fault an entire multi-GB file into memory.
enum FileProbe {
    static func read(_ url: URL) throws -> (bytes: UInt64, sampledBytes: UInt64, milliseconds: Double, checksum: UInt64) {
        let active = url.startAccessingSecurityScopedResource()
        defer { if active { url.stopAccessingSecurityScopedResource() } }
        let fd = Darwin.open(url.path, O_RDONLY)
        guard fd >= 0 else { throw CoreFailure(message: "Files could not open this file. Download it locally first.") }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0 else { throw CoreFailure(message: "Choose a nonempty, locally available file.") }
        let size = Int(info.st_size)
        let start = ContinuousClock.now
        let address = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
        guard address != MAP_FAILED, let address else { throw CoreFailure(message: "The file could not be memory mapped.") }
        defer { munmap(address, size) }
        let page = Int(getpagesize())
        let samples = min((size + page - 1) / page, (64 * 1_024 * 1_024) / page)
        var checksum: UInt64 = 0
        for index in 0..<samples {
            let offset = samples == 1 ? 0 : index * ((size - 1) / (samples - 1))
            checksum &+= UInt64(address.load(fromByteOffset: offset, as: UInt8.self))
        }
        let duration = start.duration(to: .now).components
        return (UInt64(size), UInt64(min(size, samples * page)), Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15, checksum)
    }
}

struct EvalAssetMetadata: Sendable {
    var modelFile: String
    var modelSHA256: String
    var packManifests: [String: String]
}
