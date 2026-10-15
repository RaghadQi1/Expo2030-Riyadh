import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct SmartRoutingAPISmoke {
    static func main() async throws {
        let api = try ExpoAPI(baseURL: URL(string: "http://127.0.0.1:8011"))
        let data = try await api.loadDataset()
        let graph = ExpoGraphs.indoor(data)
        let predicted = try await api.loadIndoorCrowd(graph: graph)
        let indoorEdges = graph.edges.filter { !$0.isVertical }
        guard predicted.count == indoorEdges.count else {
            fatalError("Some indoor corridors were not predicted")
        }
        for id in ["B013", "B014", "B015", "B016"] {
            let origin = graph.nodes["f1/entrance"]!.position
            let standard = graph.shortestPath(from: origin, to: "space/\(id)")!
            let fast = graph.shortestPath(from: origin, to: "space/\(id)", timeFactors: predicted)!
            guard fast.end == standard.end, fast.seconds > 0 else {
                fatalError("Destination changed for \(id)")
            }
            print("\(id): standard \(Int(standard.metres))m / \(String(format:"%.1f",standard.seconds))s, predicted fastest \(Int(fast.metres))m / \(String(format:"%.1f",fast.seconds))s")
        }
        print("SWIFT ↔ FASTAPI ↔ RANDOM FOREST ↔ DIJKSTRA: SUCCESS (\(predicted.count) corridor weights)")
    }
}
