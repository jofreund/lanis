import Foundation

public struct School: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let city: String
    public let district: String

    public init(id: Int, name: String, city: String, district: String) {
        self.id = id; self.name = name; self.city = city; self.district = district
    }

    /// "Eingabe-Schule (Musterstadt)" etc. — strips the visible id suffix SPH adds.
    public var displayName: String { name }
}

/// Public school list used by the login screen. Port of `school_selector.dart`.
public enum SchoolDirectory {
    /// SPH payload: `[{ "Name": "<Landkreis>", "Schulen": [{ "Id": "5151", "Name": "...", "Ort": "..." }] }]`
    public static func decode(_ data: Data) throws -> [School] {
        struct Entry: Decodable { let Id: String; let Name: String; let Ort: String }
        struct District: Decodable { let Name: String; let Schulen: [Entry] }
        let districts = try JSONDecoder().decode([District].self, from: data)
        return districts.flatMap { d in
            d.Schulen.compactMap { e in
                guard let id = Int(e.Id) else { return nil }
                return School(id: id, name: e.Name, city: e.Ort, district: d.Name)
            }
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public static func fetch(config: LanisConfig = .default()) async throws -> [School] {
        var req = URLRequest(url: SPH.schoolList)
        req.setValue(config.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw LanisError.network }
        return try decode(data)
    }
}
