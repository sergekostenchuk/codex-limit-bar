import Foundation

struct OpenAIStatusClient: Sendable {
    private let endpoint = URL(string: "https://status.openai.com/api/v2/incidents.json")!

    func fetchIncidents() async throws -> [RadarStatusIncident] {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexLimitBar/1.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try Self.decodeIncidents(from: data)
    }

    static func decodeIncidents(from data: Data) throws -> [RadarStatusIncident] {
        let payload = try JSONDecoder().decode(StatusResponse.self, from: data)
        return payload.incidents.compactMap { incident in
            guard let createdAt = RadarDateParser.parse(incident.createdAt) else { return nil }
            return RadarStatusIncident(
                id: incident.id,
                name: incident.name,
                status: incident.status,
                impact: incident.impact,
                createdAt: createdAt,
                resolvedAt: incident.resolvedAt.flatMap(RadarDateParser.parse)
            )
        }
    }
}

private struct StatusResponse: Decodable {
    let incidents: [StatusIncident]
}

private struct StatusIncident: Decodable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let createdAt: String
    let resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case impact
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}
