import Foundation

struct SourceNote: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var text: String
}

enum EvidenceStatus: String, Codable {
    case verified = "VERIFIED"
    case open = "OPEN"
    case unknown = "UNKNOWN"
}

struct JournalSource: Codable, Equatable {
    var sourceID: UUID
    var name: String
    var line: Int
}

struct JournalEntry: Codable, Equatable, Identifiable {
    var id: String
    var status: EvidenceStatus
    var createdAt: Date?
    var question: String?
    var evidence: String
    var sources: [JournalSource]
}

struct VaultData: Codable, Equatable {
    static let currentVersion = 1

    var notes = ""
    var mission: String?
    var sources: [SourceNote] = []
    var journal: [JournalEntry] = []

    static let firstLaunch = VaultData(
        notes: "Jezgra ostaje ista kroz vrijeme. Svaki krug je vremenski presjek. Trigram ima tri bita; 8 × 8 daje 64 uređena para. Potrebno je precizirati očuvanu veličinu i vezu s postojećim lemama."
    )

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, notes, mission, sources, journal
    }

    init(notes: String = "") {
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let version = fields.contains(.schemaVersion)
            ? try fields.decode(Int.self, forKey: .schemaVersion) : nil
        if let version, version != Self.currentVersion {
            throw VaultError.unsupportedVersion(version)
        }

        notes = try fields.decode(String.self, forKey: .notes)
        mission = try fields.decodeIfPresent(String.self, forKey: .mission)
        sources = try fields.decode([SourceNote].self, forKey: .sources)
        if version == nil {
            let entries = try fields.decode([String].self, forKey: .journal)
            journal = entries.enumerated().map { index, text in
                JournalEntry(id: "legacy-\(index)", status: .unknown, evidence: text, sources: [])
            }
        } else {
            journal = try fields.decode([JournalEntry].self, forKey: .journal)
        }
        guard Set(sources.map(\.id)).count == sources.count,
              Set(journal.map(\.id)).count == journal.count else {
            throw VaultError.duplicateID
        }
    }

    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(Self.currentVersion, forKey: .schemaVersion)
        try fields.encode(notes, forKey: .notes)
        try fields.encodeIfPresent(mission, forKey: .mission)
        try fields.encode(sources, forKey: .sources)
        try fields.encode(journal, forKey: .journal)
    }
}

enum VaultError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateID
    case writesBlocked
    case changedOnDisk
    case invalidFile
    case missingOriginal

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Nepodržana verzija vaulta (\(version))."
        case .duplicateID: "Vault sadrži ponovljene identifikatore."
        case .writesBlocked: "Upis je blokiran dok se vault ne učita ili oporavi."
        case .changedOnDisk: "Vault se promijenio na disku. Izvezi trenutnu evidenciju prije ponovnog otvaranja."
        case .invalidFile: "Vault treba biti obična datoteka."
        case .missingOriginal: "Originalni vault nije dostupan za izvoz."
        }
    }
}

// The app owns one instance on the main actor, including across windows.
final class VaultStorage {
    private let directory: URL
    private let fileManager = FileManager.default
    private var fileURL: URL { directory.appendingPathComponent("vault.json") }
    private var backupDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    private var baseline: Data?
    private(set) var savedData: VaultData?

    init(directory: URL) {
        self.directory = directory
    }

    func load() throws -> VaultData {
        savedData = nil
        baseline = nil
        let original = try readOriginal()
        let document = try original.map { try JSONDecoder().decode(VaultData.self, from: $0) }
            ?? .firstLaunch
        baseline = original
        savedData = document
        return document
    }

    func save(_ document: VaultData) throws {
        guard let savedData else { throw VaultError.writesBlocked }
        guard try readOriginal() == baseline else { throw VaultError.changedOnDisk }
        guard savedData != document else { return }

        let bytes = try encoded(document)
        if let baseline,
           try JSONDecoder().decode(VersionField.self, from: baseline).schemaVersion == nil {
            try archive(baseline, label: "pre-migration")
        }
        try commit(document, bytes: bytes, replacing: baseline)
    }

    func export(_ document: VaultData) throws -> Data {
        guard savedData != nil else { throw VaultError.writesBlocked }
        return try encoded(document)
    }

    func exportOriginal() throws -> Data {
        guard let original = try readOriginal() else { throw VaultError.missingOriginal }
        return original
    }

    func backupURLs() -> [URL] {
        let urls = try? fileManager.contentsOfDirectory(
            at: backupDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles
        )
        return (urls ?? []).filter {
            $0.pathExtension == "json" && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func restore(from bytes: Data, preserving current: VaultData) throws -> VaultData {
        let restored = try JSONDecoder().decode(VaultData.self, from: bytes)
        let replacement = try encoded(restored)
        let original = try readOriginal()
        if let original {
            try archive(original, label: "pre-restore")
        }
        if let savedData, current != savedData {
            try archive(try encoded(current), label: "unsaved")
        }
        try commit(restored, bytes: replacement, replacing: original)
        return restored
    }

    private struct VersionField: Decodable {
        let schemaVersion: Int?
    }

    private func readOriginal() throws -> Data? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile
            || error.code == .fileReadNoSuchFile {
            return nil
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw VaultError.invalidFile
        }
        return try Data(contentsOf: fileURL)
    }

    private func encoded(_ document: VaultData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    private func archive(_ bytes: Data, label: String) throws {
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let milliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        let url = backupDirectory.appendingPathComponent("\(milliseconds)-\(label)-\(UUID().uuidString).json")
        try bytes.write(to: url, options: .atomic)
    }

    private func commit(_ document: VaultData, bytes: Data, replacing original: Data?) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try readOriginal() == original else { throw VaultError.changedOnDisk }
        if original == nil {
            // Publish complete bytes without replacing a vault created since the check.
            let staged = directory.appendingPathComponent(".vault-\(UUID().uuidString)")
            defer { try? fileManager.removeItem(at: staged) }
            try bytes.write(to: staged, options: .atomic)
            try fileManager.linkItem(at: staged, to: fileURL)
        } else {
            try bytes.write(to: fileURL, options: .atomic)
        }
        baseline = bytes
        savedData = document
    }
}
