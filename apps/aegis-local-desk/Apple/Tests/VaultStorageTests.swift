import Foundation

private enum TestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): message
        }
    }
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw TestFailure.assertion(message) }
}

private func expectError(_ expected: VaultError, _ action: () throws -> Void) throws {
    do {
        try action()
        throw TestFailure.assertion("Expected \(expected)")
    } catch let actual as VaultError where actual == expected {
        return
    }
}

private func expectFailure(_ message: String, _ action: () throws -> Void) throws {
    do {
        try action()
    } catch {
        return
    }
    throw TestFailure.assertion(message)
}

private struct Fixture {
    let directory: URL
    var file: URL { directory.appendingPathComponent("vault.json") }
    var backupDirectory: URL { directory.appendingPathComponent("Backups") }

    static let legacy = Data(#"""
    {
      "notes": "Bilješka — Ω",
      "mission": "Očuvaj",
      "sources": [{"id":"86F2225F-E913-4C00-8846-A4F13A52FD8A","name":"T.lean","text":"theorem\nnext"}],
      "journal": ["Nov 26\nQ: Pitanje\nUNVERIFIED: Predlog", "Nov 26\nQ: Pitanje\nUNVERIFIED: Predlog"]
    }
    """#.utf8)

    func open() throws -> (VaultStorage, VaultData) {
        let storage = VaultStorage(directory: directory)
        return (storage, try storage.load())
    }
}

@main struct VaultStorageTests {
    static func main() {
        let tests: [(String, (Fixture) throws -> Void)] = [
            ("malformed vault blocks repeated saves and retains exact bytes", malformedVault),
            ("invalid schema and future versions remain read-only", invalidSchema),
            ("missing vault supports first save and restart", firstSave),
            ("legacy migration preserves notes, mission, source IDs and journal", migrate),
            ("optional legacy mission may be absent", legacyWithoutMission),
            ("export round-trips versioned evidence and restores after restart", exportRoundTrip),
            ("invalid restore leaves the active vault and draft unchanged", invalidRestore),
            ("recovery archives corrupt original byte-for-byte", recoverCorrupt),
            ("restore from legacy JSON saves both prior vault and pending edits", restoreLegacy),
            ("archive failure blocks migration and restore", archiveFailure),
            ("stale writers cannot replace another vault", staleWriter),
            ("non-regular vault blocks save and restore", nonRegularVault)
        ]
        var failures = 0
        for (name, test) in tests {
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AEGISVaultTest-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: directory) }
                try test(Fixture(directory: directory))
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(tests.count - failures)/\(tests.count) passed")
        if failures > 0 { exit(1) }
    }

    private static func malformedVault(_ fixture: Fixture) throws {
        let original = Data([0x7B, 0xFF, 0x0A])
        try original.write(to: fixture.file)
        for _ in 0..<2 {
            let storage = VaultStorage(directory: fixture.directory)
            try expectFailure("malformed vault loaded") { _ = try storage.load() }
            try expectError(VaultError.writesBlocked) { try storage.save(.firstLaunch) }
            try expectError(VaultError.writesBlocked) { _ = try storage.export(.firstLaunch) }
            try expect(try storage.exportOriginal() == original, "original export altered the bytes")
            try expect(try Data(contentsOf: fixture.file) == original, "save changed unreadable vault")
            try expect(storage.backupURLs().isEmpty, "blocked save created an archive")
        }
    }

    private static func invalidSchema(_ fixture: Fixture) throws {
        let future = Data(#"{"schemaVersion":2,"notes":"future","sources":[],"journal":[]}"#.utf8)
        try future.write(to: fixture.file)
        let storage = VaultStorage(directory: fixture.directory)
        try expectError(VaultError.unsupportedVersion(2)) { _ = try storage.load() }
        try expectError(VaultError.writesBlocked) { try storage.save(.firstLaunch) }
        try expect(try Data(contentsOf: fixture.file) == future, "future version changed")
        for invalid in [
            #"{"schemaVersion":null,"notes":"n","sources":[],"journal":[]}"#,
            #"{"notes":"missing arrays"}"#,
            #"{"schemaVersion":1,"notes":"n","sources":[],"journal":["legacy text"]}"#,
            #"{"schemaVersion":1,"notes":"n","sources":[],"journal":[{"id":"a","status":"UNKNOWN","evidence":"x","sources":[]},{"id":"a","status":"OPEN","evidence":"y","sources":[]}]}"#
        ] {
            let bytes = Data(invalid.utf8)
            try bytes.write(to: fixture.file)
            try expectFailure("invalid fields accepted") { _ = try storage.load() }
            try expectError(VaultError.writesBlocked) { try storage.save(.firstLaunch) }
            try expect(try Data(contentsOf: fixture.file) == bytes, "invalid vault changed")
        }
    }

    private static func firstSave(_ fixture: Fixture) throws {
        let (storage, initial) = try fixture.open()
        try expect(initial == .firstLaunch, "first launch did not receive the starter note")
        try storage.save(initial)
        try expect(!FileManager.default.fileExists(atPath: fixture.file.path), "idle launch wrote a file")
        var changed = initial
        changed.notes = "Sačuvano"
        try storage.save(changed)
        let (_, reopened) = try fixture.open()
        try expect(reopened == changed, "first save did not survive reopen")
    }

    private static func migrate(_ fixture: Fixture) throws {
        try Fixture.legacy.write(to: fixture.file)
        let (storage, legacy) = try fixture.open()
        try expect(legacy.notes == "Bilješka — Ω" && legacy.mission == "Očuvaj", "legacy notes or mission changed")
        try expect(legacy.sources.first?.id.uuidString == "86F2225F-E913-4C00-8846-A4F13A52FD8A", "source ID changed")
        try expect(legacy.sources.first?.text == "theorem\nnext", "source text changed")
        try expect(legacy.journal.map(\.id) == ["legacy-0", "legacy-1"], "IDs are not deterministic")
        try expect(legacy.journal.allSatisfy {
            $0.evidence == "Nov 26\nQ: Pitanje\nUNVERIFIED: Predlog" && $0.status == .unknown &&
            $0.createdAt == nil && $0.question == nil && $0.sources.isEmpty
        }, "migration changed text or inferred missing provenance")
        try storage.save(legacy)
        try expect(try Data(contentsOf: fixture.file) == Fixture.legacy, "read-only launch rewrote legacy bytes")

        var updated = legacy
        updated.mission = "Sačuvano"
        try storage.save(updated)
        try expect(storage.backupURLs().count == 1, "migration must create one archive")
        let archive = try Data(contentsOf: storage.backupURLs()[0])
        try expect(archive == Fixture.legacy, "legacy archive is not byte-identical")
        let (reopenedStorage, reopened) = try fixture.open()
        try expect(reopened == updated, "legacy migration did not survive restart")
        try reopenedStorage.save(reopened)
        try expect(reopenedStorage.backupURLs().count == 1, "no-op save duplicated the archive")
    }

    private static func legacyWithoutMission(_ fixture: Fixture) throws {
        let old = Data(#"{"notes":"older","sources":[],"journal":[]}"#.utf8)
        try old.write(to: fixture.file)
        let (_, loaded) = try fixture.open()
        try expect(loaded.notes == "older" && loaded.mission == nil, "optional mission was required")
    }

    private static func exportRoundTrip(_ fixture: Fixture) throws {
        let (storage, initial) = try fixture.open()
        var draft = initial
        let source = SourceNote(name: "Source.lean", text: "record")
        draft.sources = [source]
        draft.journal = [
            JournalEntry(id: "entry-1", status: .unknown, createdAt: Date(timeIntervalSince1970: 100),
                         question: "Šta znamo?", evidence: "Odgovor",
                         sources: [JournalSource(sourceID: source.id, name: source.name, line: 1)])
        ]
        let bytes = try storage.export(draft)
        let json = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
        try expect(json?["schemaVersion"] as? Int == VaultData.currentVersion, "export has no current version")
        try expect(!FileManager.default.fileExists(atPath: fixture.file.path), "export altered vault on disk")
        try expect(try storage.restore(from: bytes, preserving: initial) == draft, "returned restore data changed")
        let (_, reopened) = try fixture.open()
        try expect(reopened == draft, "round trip changed evidence or source references")
    }

    private static func invalidRestore(_ fixture: Fixture) throws {
        try Fixture.legacy.write(to: fixture.file)
        let (storage, active) = try fixture.open()
        let draft = VaultData(notes: "Nespremljeno")
        try expectFailure("bad restore was accepted") {
            _ = try storage.restore(from: Data("not JSON".utf8), preserving: draft)
        }
        try expect(try Data(contentsOf: fixture.file) == Fixture.legacy, "invalid restore changed vault bytes")
        try expect(storage.savedData == active, "invalid restore changed saved model")
        try expect(storage.backupURLs().isEmpty, "invalid restore archived data before validation")
        try expect(try JSONDecoder().decode(VaultData.self, from: storage.export(draft)) == draft,
                   "draft export unavailable after invalid restore")
    }

    private static func recoverCorrupt(_ fixture: Fixture) throws {
        let damaged = Data("{ truncated".utf8)
        try damaged.write(to: fixture.file)
        let storage = VaultStorage(directory: fixture.directory)
        try expectFailure("corrupt vault loaded") { _ = try storage.load() }
        let restored = try storage.restore(from: Fixture.legacy, preserving: VaultData())
        try expect(storage.savedData == restored, "successful restore did not unlock vault")
        let (reopened, document) = try fixture.open()
        try expect(reopened.backupURLs().count == 1, "original backup missing after restart")
        try expect(try Data(contentsOf: reopened.backupURLs()[0]) == damaged, "original backup changed")
        try expect(document == restored, "restored document did not reopen")
        var changed = document
        changed.notes = "Nastavak"
        try reopened.save(changed)
        try expect(try fixture.open().1 == changed, "save failed after recovery")
    }

    private static func restoreLegacy(_ fixture: Fixture) throws {
        let (storage, initial) = try fixture.open()
        var persisted = initial
        persisted.notes = "Prethodno"
        try storage.save(persisted)
        let previousBytes = try Data(contentsOf: fixture.file)
        var pending = persisted
        pending.notes = "Nespremljeno"
        _ = try storage.restore(from: Fixture.legacy, preserving: pending)
        let archives = storage.backupURLs()
        try expect(archives.count == 2, "persisted vault and draft must both survive")
        guard let prior = archives.first(where: { $0.lastPathComponent.contains("-pre-restore-") }),
              let unsaved = archives.first(where: { $0.lastPathComponent.contains("-unsaved-") }) else {
            throw TestFailure.assertion("expected both pre-restore and unsaved archives")
        }
        try expect(try Data(contentsOf: prior) == previousBytes, "previous version altered")
        try expect(try JSONDecoder().decode(VaultData.self, from: Data(contentsOf: unsaved)) == pending,
                   "unsaved edits were not archived")
        try expect(try fixture.open().1.notes == "Bilješka — Ω", "selected legacy backup was not restored")
    }

    private static func archiveFailure(_ fixture: Fixture) throws {
        try Fixture.legacy.write(to: fixture.file)
        try Data("obstruction".utf8).write(to: fixture.backupDirectory)
        let (storage, loaded) = try fixture.open()
        let changed = VaultData(notes: "Ne smije prepisati")
        try expectFailure("saved without archiving legacy original") { try storage.save(changed) }
        try expectFailure("restored without archiving original") {
            _ = try storage.restore(from: Fixture.legacy, preserving: changed)
        }
        try expect(try Data(contentsOf: fixture.file) == Fixture.legacy, "archive failure changed original")
        try expect(storage.savedData == loaded, "archive failure changed saved state")
    }

    private static func staleWriter(_ fixture: Fixture) throws {
        let (first, _) = try fixture.open()
        let (second, _) = try fixture.open()
        let winner = VaultData(notes: "Drugi pisac")
        try second.save(winner)
        try expectError(VaultError.changedOnDisk) { try first.save(VaultData(notes: "Zastarjelo")) }
        let (stale, _) = try fixture.open()
        let newer = VaultData(notes: "Nova izmjena")
        try second.save(newer)
        try expectError(VaultError.changedOnDisk) { try stale.save(winner) }
        try expect(try fixture.open().1 == newer, "stale saves overwrote the current vault")
    }

    private static func nonRegularVault(_ fixture: Fixture) throws {
        try FileManager.default.createDirectory(at: fixture.file, withIntermediateDirectories: false)
        let storage = VaultStorage(directory: fixture.directory)
        try expectError(VaultError.invalidFile) { _ = try storage.load() }
        try expectError(VaultError.writesBlocked) { try storage.save(.firstLaunch) }
        try expectError(VaultError.invalidFile) {
            _ = try storage.restore(from: Fixture.legacy, preserving: .firstLaunch)
        }
        try expect(storage.backupURLs().isEmpty, "invalid vault path created an archive")
    }
}
