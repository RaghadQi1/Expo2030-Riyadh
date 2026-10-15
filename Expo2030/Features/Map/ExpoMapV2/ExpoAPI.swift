import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Native REST client. The iPhone simulator reaches the Mac host on localhost.
/// For a real iPhone change EXPO_API_BASE_URL in Info.plist to the Mac's LAN IP.
struct ExpoAPI {
    private let baseURL: URL

    init(baseURL overrideURL: URL? = nil) throws {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "EXPO_API_BASE_URL") as? String)
            ?? "http://127.0.0.1:8001"
        guard let url = overrideURL ?? URL(string: raw),
              ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil else { throw ExpoAPIError.invalidURL }
        baseURL = url
    }

    func loadDataset() async throws -> ExpoDataset {
        let url = baseURL.appending(path: "api/v1/dataset")
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw ExpoAPIError.badResponse
        }
        let remote = try JSONDecoder().decode(RemoteExpoDataset.self, from: data)
        let dataset = ExpoDataset(map: remote.map, booths: remote.booths, events: remote.events,
                                  assignments: remote.assignments, indoor: remote.indoor, gates: remote.gates)
        let issues = dataset.validate()
        guard issues.isEmpty else { throw ExpoDataError.inconsistent(issues.joined(separator: ", ")) }
        return dataset
    }

    /// One batched prediction for every traversable indoor graph edge.
    /// The graph is the source of truth for physical corridor coordinates.
    func loadIndoorCrowd(graph: NavigationGraph, date: Date = Date(),
                         overrideHour: Int? = nil, overrideDay: Int? = nil) async throws -> [String: Double] {
        guard graph.zone == .indoor else { throw ExpoAPIError.badResponse }
        let calendar = Calendar.current
        let hour = overrideHour ?? calendar.component(.hour, from: date)
        let day = overrideDay ?? (calendar.component(.weekday, from: date) - 1)  // Sunday = 0
        guard (0...23).contains(hour), (0...6).contains(day) else { throw ExpoAPIError.badResponse }
        let edges: [IndoorCorridorQuery] = graph.edges.compactMap { edge in
            guard !edge.isVertical, let from = graph.nodes[edge.from]?.position,
                  let to = graph.nodes[edge.to]?.position,
                  from.floor == to.floor else { return nil }
            return IndoorCorridorQuery(edge_id: edge.key, floor: from.floor,
                x: (from.point.x + to.point.x) / 2,
                y: (from.point.y + to.point.y) / 2)
        }
        guard !edges.isEmpty else { throw ExpoAPIError.diagnostic("لم يتم العثور على ممرات للمودل") }
        guard edges.count <= 256 else { throw ExpoAPIError.diagnostic("عدد الممرات \(edges.count) يتجاوز حد الخادم 256") }
        var request = URLRequest(url: baseURL.appending(path: "api/v1/crowd/indoor-edges"))
        request.httpMethod = "POST"
        request.timeoutInterval = 25  // Model may train on the first request.
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(IndoorCrowdRequest(hour: hour, day: day, edges: edges))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ExpoAPIError.diagnostic("لا توجد استجابة HTTP من الخادم") }
        guard (200...299).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExpoAPIError.diagnostic("HTTP \(response.statusCode): \(String(body.prefix(200)))")
        }
        let estimate: IndoorCrowdResponse
        do { estimate = try JSONDecoder().decode(IndoorCrowdResponse.self, from: data) }
        catch { throw ExpoAPIError.diagnostic("تعذرت قراءة توقعات الممرات: \(error.localizedDescription)") }
        guard estimate.simulation, estimate.predictions.count == edges.count else {
            throw ExpoAPIError.diagnostic("عدد النتائج \(estimate.predictions.count) لا يطابق الممرات \(edges.count)")
        }
        var factors: [String: Double] = [:]
        let validKeys = Set(edges.map(\.edge_id))
        for item in estimate.predictions {
            guard validKeys.contains(item.edge_id), factors[item.edge_id] == nil,
                  item.time_factor.isFinite && (1.0...4.25).contains(item.time_factor) else { throw ExpoAPIError.badResponse }
            factors[item.edge_id] = item.time_factor
        }
        guard factors.count == edges.count else { throw ExpoAPIError.badResponse }
        return factors
    }

}

private struct RemoteExpoDataset: Decodable {
    let map: ExpoMapData
    let booths: [ExpoBooth]
    let events: [ExpoNavEvent]
    let assignments: BoothAssignments
    let indoor: SaudiIndoorData
    let gates: GatesData
}

private enum ExpoAPIError: LocalizedError {
    case invalidURL
    case badResponse
    case diagnostic(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "رابط الخادم غير صالح"
        case .badResponse: return "الخادم لم يُرجع البيانات بنجاح"
        case .diagnostic(let detail): return detail
        }
    }
}


private struct IndoorCorridorQuery: Encodable {
    let edge_id: String
    let floor: Int
    let x: Double
    let y: Double
}
private struct IndoorCrowdRequest: Encodable {
    let hour: Int
    let day: Int
    let edges: [IndoorCorridorQuery]
}
private struct IndoorCrowdResponse: Decodable {
    let simulation: Bool
    let predictions: [IndoorCrowdEdge]
}
private struct IndoorCrowdEdge: Decodable {
    let edge_id: String
    let time_factor: Double
}
