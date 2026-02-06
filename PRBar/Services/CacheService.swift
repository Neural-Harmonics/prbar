import Foundation

final class CacheService {
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("PRBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("cache.json")
    }

    func load() -> CachedState {
        guard let data = try? Data(contentsOf: fileURL) else { return CachedState() }
        return (try? JSONDecoder.prbar.decode(CachedState.self, from: data)) ?? CachedState()
    }

    func save(_ state: CachedState) {
        guard let data = try? JSONEncoder.prbar.encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension JSONDecoder {
    static var prbar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var prbar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
