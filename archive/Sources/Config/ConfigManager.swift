import Foundation

public final class ConfigManager: ObservableObject {
    @Published public private(set) var config: MrMouseConfig

    private let configURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static let shared = ConfigManager()

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MrMouse")

        self.configURL = dir.appendingPathComponent("config.json")
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        // Load existing or create default
        if let data = try? Data(contentsOf: configURL),
           let loaded = try? decoder.decode(MrMouseConfig.self, from: data) {
            self.config = loaded
        } else {
            self.config = MrMouseConfig()
        }
    }

    public func save() throws {
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: configURL, options: .atomic)
    }

    public func update(_ mutation: (inout MrMouseConfig) -> Void) throws {
        mutation(&config)
        try save()
    }

    public func profileForApp(_ bundleID: String?) -> Profile {
        if let id = bundleID, let appProfile = config.appProfiles[id] {
            return appProfile
        }
        return config.globalProfile
    }

    public func deviceConfig(for key: String) -> DeviceConfig {
        config.devices[key] ?? DeviceConfig()
    }
}
