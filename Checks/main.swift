// MavicaCore check-runner.
//
// XCTest is not part of the Command Line Tools, so these checks are a plain
// executable: `swift run MavicaChecks`. Exits non-zero on the first report of
// any failed expectation.

import Foundation
import MavicaCore

var failureCount = 0

func expect(
    _ condition: @autoclosure () -> Bool,
    _ label: String,
    file: String = #file,
    line: Int = #line
) {
    if condition() {
        print("ok      \(label)")
    } else {
        failureCount += 1
        print("FAILED  \(label)  (\((file as NSString).lastPathComponent):\(line))")
    }
}

func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ label: String,
    file: String = #file,
    line: Int = #line
) {
    if actual == expected {
        print("ok      \(label)")
    } else {
        failureCount += 1
        print("FAILED  \(label)  (\((file as NSString).lastPathComponent):\(line))")
        print("        expected: \(expected)")
        print("        actual:   \(actual)")
    }
}

let utc = TimeZone(identifier: "UTC")!
let fileManager = FileManager.default

func makeTempDir(_ name: String) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("mavica-checks-\(name)-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeFile(at url: URL, contents: String, modified: Date? = nil) throws {
    try fileManager.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data(contents.utf8).write(to: url)
    if let modified {
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

// MARK: - MavicaNamer

expectEqual(
    MavicaNamer.timestamp(for: Date(timeIntervalSince1970: 0), timeZone: utc),
    "1970-01-01-00-00-00",
    "timestamp formats epoch in UTC"
)

let feb2001 = Date(timeIntervalSince1970: 981_173_106) // 2001-02-03 04:05:06 UTC
expectEqual(
    MavicaNamer.fileName(for: feb2001, timeZone: utc) { _ in false },
    "MAVICA-2001-02-03-04-05-06.JPG",
    "file name without collision"
)

let taken: Set<String> = [
    "MAVICA-1970-01-01-00-00-00.JPG",
    "MAVICA-1970-01-01-00-00-00--2.JPG"
]
expectEqual(
    MavicaNamer.fileName(for: Date(timeIntervalSince1970: 0), timeZone: utc) { taken.contains($0) },
    "MAVICA-1970-01-01-00-00-00--3.JPG",
    "collision appends --2, --3, …"
)

// MARK: - MavicaScanner

do {
    let root = try makeTempDir("scanner")
    defer { try? fileManager.removeItem(at: root) }

    let older = Date(timeIntervalSince1970: 1_000_000)
    let newer = Date(timeIntervalSince1970: 2_000_000)
    try makeFile(at: root.appendingPathComponent("DCIM/100MSDCF/DSC00002.JPG"), contents: "b", modified: newer)
    try makeFile(at: root.appendingPathComponent("DCIM/100MSDCF/DSC00001.jpeg"), contents: "a", modified: older)
    try makeFile(at: root.appendingPathComponent("DCIM/100MSDCF/._DSC00001.jpeg"), contents: "junk", modified: older)
    try makeFile(at: root.appendingPathComponent("DCIM/notes.txt"), contents: "junk", modified: older)

    let files = MavicaScanner.jpegFiles(in: root)
    expectEqual(
        files.map(\.url.lastPathComponent),
        ["DSC00001.jpeg", "DSC00002.JPG"],
        "scanner finds JPEGs recursively, oldest first, skipping ._ sidecars and non-JPEGs"
    )
    expectEqual(
        files.map(\.modificationDate),
        [older, newer],
        "scanner reports modification dates"
    )
}

// MARK: - CopyEngine

do {
    let base = try makeTempDir("engine")
    defer { try? fileManager.removeItem(at: base) }
    let source = base.appendingPathComponent("source", isDirectory: true)
    let destination = base.appendingPathComponent("destination", isDirectory: true)

    let sourceFile = source.appendingPathComponent("DSC00001.JPG")
    try makeFile(at: sourceFile, contents: "photo-1", modified: feb2001)

    let outcome = CopyEngine().copy(
        files: [MavicaFile(url: sourceFile, modificationDate: feb2001)],
        into: destination,
        timeZone: utc
    )

    expect(outcome.failures.isEmpty, "copy reports no failures")
    expectEqual(outcome.copied.count, 1, "copy reports one copied file")
    if let copied = outcome.copied.first?.destination {
        expectEqual(copied.lastPathComponent, "MAVICA-2001-02-03-04-05-06.JPG", "copy renames by modification date")
        expectEqual(try String(contentsOf: copied, encoding: .utf8), "photo-1", "copy preserves contents")
        let attributes = try fileManager.attributesOfItem(atPath: copied.path)
        expectEqual(attributes[.creationDate] as? Date, feb2001, "copy sets creation date to source mtime")
        expectEqual(attributes[.modificationDate] as? Date, feb2001, "copy sets modification date to source mtime")
    }
}

do {
    let base = try makeTempDir("engine-collision")
    defer { try? fileManager.removeItem(at: base) }
    let source = base.appendingPathComponent("source", isDirectory: true)
    let destination = base.appendingPathComponent("destination", isDirectory: true)

    let epoch = Date(timeIntervalSince1970: 0)
    let first = source.appendingPathComponent("DSC00001.JPG")
    let second = source.appendingPathComponent("DSC00002.JPG")
    try makeFile(at: first, contents: "a", modified: epoch)
    try makeFile(at: second, contents: "b", modified: epoch)

    let outcome = CopyEngine().copy(
        files: [
            MavicaFile(url: first, modificationDate: epoch),
            MavicaFile(url: second, modificationDate: epoch)
        ],
        into: destination,
        timeZone: utc
    )
    expectEqual(
        outcome.copied.map(\.destination.lastPathComponent),
        ["MAVICA-1970-01-01-00-00-00.JPG", "MAVICA-1970-01-01-00-00-00--2.JPG"],
        "same-second photos get suffixed names"
    )
}

do {
    let base = try makeTempDir("engine-missing")
    defer { try? fileManager.removeItem(at: base) }
    let destination = base.appendingPathComponent("destination", isDirectory: true)
    let missing = base.appendingPathComponent("GONE.JPG")

    let outcome = CopyEngine().copy(
        files: [MavicaFile(url: missing, modificationDate: Date(timeIntervalSince1970: 0))],
        into: destination,
        timeZone: utc
    )
    expect(outcome.copied.isEmpty, "missing source copies nothing")
    expectEqual(outcome.failures.count, 1, "missing source is reported as a failure")
}

// MARK: - Summary

if failureCount > 0 {
    print("\n\(failureCount) check(s) FAILED")
    exit(1)
} else {
    print("\nAll checks passed.")
}
