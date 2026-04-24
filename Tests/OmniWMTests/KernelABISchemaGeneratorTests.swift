// SPDX-License-Identifier: GPL-2.0-only

import COmniWMKernels
import Foundation
import Testing


private enum KernelABIArtifactPaths {
    static func packageRoot(testFilePath: StaticString = #filePath) -> URL {
        let testFile = URL(fileURLWithPath: "\(testFilePath)")
        return testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func goldensFile(testFilePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(testFilePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("KernelABIGoldens.swift")
    }

    static func validatorFile(testFilePath: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(testFilePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("KernelABIRuntimeValidator.swift")
    }

    static func generatedCHeader(testFilePath: StaticString = #filePath) -> URL {
        packageRoot(testFilePath: testFilePath)
            .appendingPathComponent("Sources/COmniWMKernels/include/omniwm_kernels_generated.h")
    }

    static func generatedZigAssertions(testFilePath: StaticString = #filePath) -> URL {
        packageRoot(testFilePath: testFilePath)
            .appendingPathComponent("Zig/omniwm_kernels/src/abi_schema_assertions.zig")
    }
}


enum KernelABISchemaGeneratorBackend {
    static func renderGoldens(_ entries: [KernelABISchemaEntry], schemaVersion: Int) -> String {
        var output = ""
        output += "// SPDX-License-Identifier: GPL-2.0-only\n"
        output += "//\n"
        output += "// ABI-07 (Phase 06): committed snapshot of the kernel ABI struct layouts.\n"
        output += "//\n"
        output += "// GENERATED FILE — do not edit by hand. Regenerate with:\n"
        output += "//\n"
        output += "//     make regen-kernel-abi-goldens\n"
        output += "//\n"
        output += "// `KernelABISchemaGeneratorTests` enforces this file matches\n"
        output += "// `KernelABISchema.currentLayouts()` on every test run; drift fails the\n"
        output += "// test, the regen target rewrites this file from the live `MemoryLayout`\n"
        output += "// values and re-verifies.\n"
        output += "\n"
        output += "import Foundation\n"
        output += "\n"
        output += "enum KernelABIGoldens {\n"
        output += "    static let schemaVersion: Int = \(schemaVersion)\n"
        output += "    static let entries: [KernelABISchemaEntry] = [\n"
        for entry in entries {
            output += "        KernelABISchemaEntry(name: \"\(entry.name)\", size: \(entry.size), stride: \(entry.stride), alignment: \(entry.alignment)),\n"
        }
        output += "    ]\n"
        output += "}\n"
        return output
    }

    static func renderValidator(_ entries: [KernelABISchemaEntry], schemaVersion: Int) -> String {
        var output = ""
        output += "// SPDX-License-Identifier: GPL-2.0-only\n"
        output += "//\n"
        output += "// ABI-07 (Phase 06): generated Swift validation helpers for the kernel ABI.\n"
        output += "//\n"
        output += "// GENERATED FILE — do not edit by hand. Regenerate with:\n"
        output += "//\n"
        output += "//     make regen-kernel-abi-goldens\n"
        output += "//\n"
        output += "// `KernelABIRuntimeValidator.validate()` returns a list of layout\n"
        output += "// mismatches between the live `MemoryLayout<T>` values and the committed\n"
        output += "// goldens. An empty array means the runtime layout matches the schema.\n"
        output += "// `KernelABIRuntimeValidator.expectedSchemaVersion` is the version baked\n"
        output += "// into this generated file; callers should compare against\n"
        output += "// `KernelABISchema.schemaVersion` to detect cross-artifact version skew.\n"
        output += "\n"
        output += "import COmniWMKernels\n"
        output += "import Foundation\n"
        output += "\n"
        output += "enum KernelABIRuntimeValidator {\n"
        output += "    struct Mismatch: Equatable {\n"
        output += "        let name: String\n"
        output += "        let expected: KernelABISchemaEntry\n"
        output += "        let actual: KernelABISchemaEntry\n"
        output += "    }\n"
        output += "\n"
        output += "    static let expectedSchemaVersion: Int = \(schemaVersion)\n"
        output += "\n"
        output += "    static func validate() -> [Mismatch] {\n"
        output += "        var mismatches: [Mismatch] = []\n"
        for entry in entries {
            output += "        check(\"\(entry.name)\", \(entry.name).self, expected: KernelABISchemaEntry(name: \"\(entry.name)\", size: \(entry.size), stride: \(entry.stride), alignment: \(entry.alignment)), into: &mismatches)\n"
        }
        output += "        return mismatches\n"
        output += "    }\n"
        output += "\n"
        output += "    private static func check<T>(\n"
        output += "        _ name: String,\n"
        output += "        _ type: T.Type,\n"
        output += "        expected: KernelABISchemaEntry,\n"
        output += "        into mismatches: inout [Mismatch]\n"
        output += "    ) {\n"
        output += "        let actual = KernelABISchemaEntry(\n"
        output += "            name: name,\n"
        output += "            size: MemoryLayout<T>.size,\n"
        output += "            stride: MemoryLayout<T>.stride,\n"
        output += "            alignment: MemoryLayout<T>.alignment\n"
        output += "        )\n"
        output += "        if actual != expected {\n"
        output += "            mismatches.append(Mismatch(name: name, expected: expected, actual: actual))\n"
        output += "        }\n"
        output += "    }\n"
        output += "}\n"
        return output
    }

    static func renderCHeader(_ entries: [KernelABISchemaEntry], schemaVersion: Int) -> String {
        var output = ""
        output += "// SPDX-License-Identifier: GPL-2.0-only\n"
        output += "//\n"
        output += "// ABI-07 (Phase 06): generated C header with size/alignment parity\n"
        output += "// assertions for every stable typedef in `omniwm_kernels.h`.\n"
        output += "//\n"
        output += "// GENERATED FILE — do not edit by hand. Regenerate with:\n"
        output += "//\n"
        output += "//     make regen-kernel-abi-goldens\n"
        output += "//\n"
        output += "// Included by `Sources/COmniWMKernels/bridge.c` so any drift between the\n"
        output += "// hand-written kernel header and the schema fails the C compile of the\n"
        output += "// kernel target. `_Static_assert` is the C11 mechanism; the kernel\n"
        output += "// target compiles with C11 already.\n"
        output += "\n"
        output += "#ifndef OMNIWM_KERNELS_GENERATED_H\n"
        output += "#define OMNIWM_KERNELS_GENERATED_H\n"
        output += "\n"
        output += "#include \"omniwm_kernels.h\"\n"
        output += "\n"
        output += "#define OMNIWM_KERNELS_ABI_SCHEMA_VERSION \(schemaVersion)\n"
        output += "\n"
        for entry in entries {
            output += "_Static_assert(sizeof(\(entry.name)) == \(entry.size), \"ABI drift: sizeof(\(entry.name))\");\n"
            output += "_Static_assert(_Alignof(\(entry.name)) == \(entry.alignment), \"ABI drift: _Alignof(\(entry.name))\");\n"
        }
        output += "\n"
        output += "#endif /* OMNIWM_KERNELS_GENERATED_H */\n"
        return output
    }

    static func renderZigAssertions(_ entries: [KernelABISchemaEntry], schemaVersion: Int) -> String {
        var output = ""
        output += "// SPDX-License-Identifier: GPL-2.0-only\n"
        output += "//\n"
        output += "// ABI-07 (Phase 06): generated Zig parity assertions for the kernel ABI.\n"
        output += "//\n"
        output += "// GENERATED FILE — do not edit by hand. Regenerate with:\n"
        output += "//\n"
        output += "//     make regen-kernel-abi-goldens\n"
        output += "//\n"
        output += "// Imports `omniwm_kernels.h` via `@cImport` and pins every typedef's\n"
        output += "// `@sizeOf` / `@alignOf` against the schema's literal goldens at\n"
        output += "// `comptime`. Wired into `root.zig` so `make kernels-test` enforces the\n"
        output += "// parity check on every Zig build.\n"
        output += "\n"
        output += "const std = @import(\"std\");\n"
        output += "const c = @cImport({\n"
        output += "    @cInclude(\"omniwm_kernels.h\");\n"
        output += "});\n"
        output += "\n"
        output += "pub const ABI_SCHEMA_VERSION: u32 = \(schemaVersion);\n"
        output += "\n"
        output += "comptime {\n"
        for entry in entries {
            output += "    std.debug.assert(@sizeOf(c.\(entry.name)) == \(entry.size));\n"
            output += "    std.debug.assert(@alignOf(c.\(entry.name)) == \(entry.alignment));\n"
        }
        output += "}\n"
        output += "\n"
        output += "// Suppress \"unused\" warning when this file is imported from `root.zig`\n"
        output += "// solely for its `comptime` block.\n"
        output += "pub fn referenced() void {}\n"
        return output
    }

    static func diff(
        committed: [KernelABISchemaEntry],
        current: [KernelABISchemaEntry]
    ) -> String {
        let committedByName = Dictionary(uniqueKeysWithValues: committed.map { ($0.name, $0) })
        let currentByName = Dictionary(uniqueKeysWithValues: current.map { ($0.name, $0) })
        var lines: [String] = []
        for entry in current {
            guard let committed = committedByName[entry.name] else {
                lines.append("ADD    \(entry.name) size=\(entry.size) stride=\(entry.stride) alignment=\(entry.alignment)")
                continue
            }
            if committed != entry {
                lines.append("CHANGE \(entry.name) committed=(\(committed.size),\(committed.stride),\(committed.alignment)) current=(\(entry.size),\(entry.stride),\(entry.alignment))")
            }
        }
        for entry in committed where currentByName[entry.name] == nil {
            lines.append("REMOVE \(entry.name) size=\(entry.size) stride=\(entry.stride) alignment=\(entry.alignment)")
        }
        return lines.joined(separator: "\n")
    }
}


@Suite struct KernelABISchemaGeneratorTests {
    @Test func goldensMatchCurrentLayouts() throws {
        let current = KernelABISchema.currentLayouts()
        let version = KernelABISchema.schemaVersion
        let regenRequested = ProcessInfo.processInfo
            .environment["OMNIWM_REGENERATE_KERNEL_ABI_GOLDENS"] == "1"

        if regenRequested {
            try regenerateAllArtifacts(current: current, schemaVersion: version)
        }

        let drift = KernelABISchemaGeneratorBackend.diff(
            committed: KernelABIGoldens.entries,
            current: current
        )
        if !drift.isEmpty {
            Issue.record("""
                Kernel ABI goldens drift detected. Run \
                `make regen-kernel-abi-goldens` to update.

                \(drift)
                """)
        }
        #expect(drift.isEmpty, "kernel ABI goldens out of date")

        #expect(KernelABIGoldens.schemaVersion == version,
                "schema version mismatch: KernelABISchema=\(version) KernelABIGoldens=\(KernelABIGoldens.schemaVersion)")

        #expect(KernelABIRuntimeValidator.expectedSchemaVersion == version,
                "schema version mismatch: KernelABISchema=\(version) KernelABIRuntimeValidator=\(KernelABIRuntimeValidator.expectedSchemaVersion)")

        let validatorMismatches = KernelABIRuntimeValidator.validate()
        if !validatorMismatches.isEmpty {
            Issue.record("""
                Generated validator reports runtime layout mismatches:

                \(validatorMismatches.map { "\($0.name): expected \($0.expected) got \($0.actual)" }.joined(separator: "\n"))
                """)
        }
        #expect(validatorMismatches.isEmpty, "generated validator out of date")

        let cHeaderURL = KernelABIArtifactPaths.generatedCHeader()
        let expectedCHeader = KernelABISchemaGeneratorBackend
            .renderCHeader(current, schemaVersion: version)
        let actualCHeader = (try? String(contentsOf: cHeaderURL, encoding: .utf8)) ?? ""
        #expect(actualCHeader == expectedCHeader,
                "generated C header (`omniwm_kernels_generated.h`) out of date — run `make regen-kernel-abi-goldens`")

        let zigURL = KernelABIArtifactPaths.generatedZigAssertions()
        let expectedZig = KernelABISchemaGeneratorBackend
            .renderZigAssertions(current, schemaVersion: version)
        let actualZig = (try? String(contentsOf: zigURL, encoding: .utf8)) ?? ""
        #expect(actualZig == expectedZig,
                "generated Zig assertions (`abi_schema_assertions.zig`) out of date — run `make regen-kernel-abi-goldens`")
    }

    private func regenerateAllArtifacts(
        current: [KernelABISchemaEntry],
        schemaVersion: Int
    ) throws {
        try KernelABISchemaGeneratorBackend
            .renderGoldens(current, schemaVersion: schemaVersion)
            .write(to: KernelABIArtifactPaths.goldensFile(), atomically: true, encoding: .utf8)
        try KernelABISchemaGeneratorBackend
            .renderValidator(current, schemaVersion: schemaVersion)
            .write(to: KernelABIArtifactPaths.validatorFile(), atomically: true, encoding: .utf8)
        try KernelABISchemaGeneratorBackend
            .renderCHeader(current, schemaVersion: schemaVersion)
            .write(to: KernelABIArtifactPaths.generatedCHeader(), atomically: true, encoding: .utf8)
        try KernelABISchemaGeneratorBackend
            .renderZigAssertions(current, schemaVersion: schemaVersion)
            .write(to: KernelABIArtifactPaths.generatedZigAssertions(), atomically: true, encoding: .utf8)
        print("Regenerated kernel ABI artifacts (schemaVersion=\(schemaVersion), \(current.count) entries):")
        print("  - \(KernelABIArtifactPaths.goldensFile().path)")
        print("  - \(KernelABIArtifactPaths.validatorFile().path)")
        print("  - \(KernelABIArtifactPaths.generatedCHeader().path)")
        print("  - \(KernelABIArtifactPaths.generatedZigAssertions().path)")
    }

    @Test func everyEntryIsSane() {
        for entry in KernelABISchema.currentLayouts() {
            #expect(entry.size > 0, "\(entry.name): size must be positive")
            #expect(entry.stride >= entry.size, "\(entry.name): stride < size")
            #expect(
                entry.alignment > 0 && (entry.alignment & (entry.alignment - 1)) == 0,
                "\(entry.name): alignment not a power of two"
            )
            #expect(entry.alignment <= 16, "\(entry.name): alignment > 16 unexpected")
        }
    }

    @Test func everyEntryAppearsExactlyOnce() {
        let names = KernelABISchema.currentLayouts().map(\.name)
        let unique = Set(names)
        #expect(names.count == unique.count, "duplicate entries in KernelABISchema")
    }

    @Test func schemaVersionIsPositive() {
        #expect(KernelABISchema.schemaVersion > 0,
                "schema version must be positive (got \(KernelABISchema.schemaVersion))")
    }
}
