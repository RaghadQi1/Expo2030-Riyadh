import Foundation

public struct MapRectangle: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(_ x: Double,_ y: Double,_ width: Double,_ height: Double) {
        self.x=x;self.y=y;self.width=width;self.height=height
    }
    public func containsInterior(_ point:ExpoNavPoint) -> Bool {
        point.x > x+0.001 && point.x < x+width-0.001 &&
        point.y > y+0.001 && point.y < y+height-0.001
    }
}
public enum IndoorGeometry {
    // Shared door-aligned walls used by the renderer and graph integrity tests.
    public static let rooms: [String: MapRectangle] = [
        "B013":.init(142,116,138,112), "B014":.init(482,116,138,112),
        "B015":.init(150,281,132,102), "B016":.init(478,281,132,102),
        "stage":.init(316,85,128,85), "cafe":.init(65,445,129,56),
        "wc":.init(267,451,67,51), "exit":.init(430,451,90,51),
        "prayer":.init(566,443,125,58),
        "lift1":.init(354,347,52,46), "lift2":.init(354,347,52,46)
    ]
    public static func routeCrossesWalls(graph:NavigationGraph, data:ExpoDataset) -> [String] {
        var issues:[String]=[]
        for edge in graph.edges where !edge.isVertical {
            guard let a=graph.nodes[edge.from]?.position,
                  let b=graph.nodes[edge.to]?.position else { continue }
            for space in data.indoor.spaces where space.floor == a.floor {
                guard let room=rooms[space.id] else { continue }
                for tick in 1..<80 {
                    let point=a.point.interpolated(to:b.point,fraction:Double(tick)/80)
                    if room.containsInterior(point) {
                        issues.append("\(edge.from) → \(edge.to) crosses room \(space.id)")
                        break
                    }
                }
            }
        }
        return issues
    }
}
public enum OutdoorGeometry {
    public static let worldScale = 0.22
    public static func buildingCenter(_ location:ExpoLocation,door:ExpoNavPoint) -> ExpoNavPoint {
        if location.id == "hub" || location.id.hasPrefix("gate") {return door}
        let parts=location.node.split(separator:",").compactMap { Int($0) }
        guard parts.count == 2 else {return door}
        let heading = -Double.pi/2 + Double(parts[1])*2*Double.pi/10 + 1.05
        let shift = location.kind == "pavilion" ? 50.0 : 20.0
        return ExpoNavPoint(door.x+cos(heading)*shift,door.y+sin(heading)*shift)
    }
    public static func footprintContains(_ p:ExpoNavPoint,building:ExpoLocation,door:ExpoNavPoint) -> Bool {
        guard building.kind == "pavilion" else {return false}
        let center=buildingCenter(building,door:door)
        let vx=door.x-center.x, vy=door.y-center.y
        let length=hypot(vx,vy)
        guard length > 0 else {return false}
        let frontX=vx/length,frontY=vy/length
        let px=p.x-center.x,py=p.y-center.y
        let localZ=px*frontX+py*frontY
        let localX=px*(-frontY)+py*frontX
        let size:Double = building.id == "sa" ? 12 : building.size == "lg" ? 9.2 : 8
        return abs(localX) < (size+2.1)/2/worldScale && abs(localZ) < (size+1.5)/2/worldScale
    }
    public static func routeCrossesPavilions(graph:NavigationGraph,data:ExpoDataset) -> [String] {
        var issues:[String]=[]
        let pavilions=data.map.locations.filter{$0.kind == "pavilion"}
        for edge in graph.edges {
            guard let a=graph.nodes[edge.from]?.position.point,
                  let b=graph.nodes[edge.to]?.position.point else {continue}
            for pavilion in pavilions {
                guard let door=graph.nodes["location/\(pavilion.id)"]?.position.point else {continue}
                for tick in 1..<60 {
                    let p=a.interpolated(to:b,fraction:Double(tick)/60)
                    if footprintContains(p,building:pavilion,door:door) {
                        issues.append("\(edge.from) → \(edge.to) crosses \(pavilion.id)")
                        break
                    }
                }
            }
        }
        return issues
    }
}
