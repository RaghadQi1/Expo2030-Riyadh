import SwiftUI
import SceneKit
import simd

private enum Expo3D {
    static let scale = 0.22
    static func world(_ point: ExpoNavPoint, height: Float = 0) -> SCNVector3 {
        SCNVector3(Float((point.x - 500)*scale), height, Float((point.y - 350)*scale))
    }
    static func point(_ vector: SCNVector3) -> ExpoNavPoint {
        ExpoNavPoint(Double(vector.x)/scale + 500, Double(vector.z)/scale + 350)
    }
    static func material(_ hex: String, metallic: CGFloat = 0, roughness: CGFloat = 0.85) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(hexString: hex)
        mat.lightingModel = .physicallyBased
        mat.metalness.contents = metallic
        mat.roughness.contents = roughness
        mat.isDoubleSided = true
        return mat
    }
    static let paths = material("#F1E7D5")
    static let pathBorder = material("#C5BBA6")
    static let sand = material("#E8DBC4")
    static let ivory = material("#F8F0E2")
    static let blue = material("#1E9AD8")
    static let forest = material("#326C58")
    static let glass = material("#8FCAC7", metallic: 0.2, roughness: 0.27)
    static let bronze = material("#B18A56", metallic: 0.6, roughness: 0.42)
    static let darkGlass = material("#33575F", metallic: 0.25, roughness: 0.28)
    static let grass = material("#ADC3A1")
    static let foliage = material("#63946A")
    static let paleGreen = material("#8DB78B")

    static func box(_ w: CGFloat,_ h: CGFloat,_ d: CGFloat,_ mat: SCNMaterial,
                    x: Float = 0,y: Float = 0,z: Float = 0) -> SCNNode {
        let node = SCNNode(geometry: SCNBox(width:w,height:h,length:d,chamferRadius: min(0.28, h/5)))
        node.geometry?.firstMaterial = mat
        node.position = SCNVector3(x,y,z)
        node.castsShadow = true
        return node
    }
    static func cylinder(_ radius: CGFloat,_ height: CGFloat,_ mat: SCNMaterial, sides: Int = 24) -> SCNNode {
        let node = SCNNode(geometry: SCNCylinder(radius: radius,height: height))
        node.geometry?.firstMaterial = mat
        node.castsShadow = true
        return node
    }
    static func segment(_ start: SCNVector3,_ end: SCNVector3,
                        diameter: CGFloat, material: SCNMaterial) -> SCNNode {
        let ax = SIMD3<Float>(start.x,start.y,start.z)
        let bx = SIMD3<Float>(end.x,end.y,end.z)
        let delta = bx - ax
        let dist = simd_length(delta)
        let node = cylinder(diameter/2, CGFloat(max(0.0001,dist)), material, sides: 8)
        node.simdPosition = (ax + bx) / 2
        if dist > 0.0001 { node.simdOrientation = simd_quatf(from: SIMD3<Float>(0,1,0), to: delta / dist) }
        node.castsShadow = false
        return node
    }
}

extension UIColor {
    convenience init(hexString: String) {
        let number = Int(hexString.replacingOccurrences(of: "#", with: ""),radix:16) ?? 0
        self.init(red:CGFloat((number>>16)&255)/255, green:CGFloat((number>>8)&255)/255,
                  blue:CGFloat(number&255)/255, alpha:1)
    }
}

struct Outdoor3DMapView: UIViewRepresentable {
    @ObservedObject var store: ExpoStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = makeScene(graph: store.outdoor, dataset: store.dataset, coordinator: context.coordinator)
        view.pointOfView = context.coordinator.camera
        view.backgroundColor = UIColor(hexString: "#D5E4E0")
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.preferredFramesPerSecond = 45
        view.isPlaying = true
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTap(_:)))
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        context.coordinator.view = view
        updateUIView(view, context: context)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        // Outdoor scene is for browsing only: no simulated visitor marker or drawn route.
        let selected = store.selectedLocationID
        if selected != coordinator.lastSelection {
            coordinator.lastSelection = selected
            if let id = selected, let point = store.outdoor.nodes["location/\(id)"]?.position.point {
                coordinator.selection.isHidden = false
                coordinator.selection.position = Expo3D.world(point, height: 0.75)
            } else { coordinator.selection.isHidden = true }
        }
        if coordinator.lastCameraRevision != store.cameraRevision {
            coordinator.lastCameraRevision = store.cameraRevision
            let center = store.position.point
            let v = Expo3D.world(center)
            let camera = coordinator.camera
            camera.position = SCNVector3(v.x+80,99,v.z+90)
            camera.look(at: SCNVector3(v.x,0,v.z))
        }
    }
    private func makeScene(graph: NavigationGraph, dataset: ExpoDataset, coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor(hexString: "#D5E4E0")
        scene.fogColor = UIColor(hexString: "#D5E4E0")
        scene.fogStartDistance = 190
        scene.fogEndDistance = 325
        let root = scene.rootNode
        let ground = Expo3D.box(220,1,220,Expo3D.grass, y:-0.75)
        ground.name = "map-ground"
        root.addChildNode(ground)
        let oasis = Expo3D.cylinder(85, 0.22, Expo3D.material("#88AD85"), sides: 100)
        oasis.position.y = -0.12
        root.addChildNode(oasis)
        let plaza = Expo3D.cylinder(11,0.55,Expo3D.ivory,sides:60)
        plaza.position.y = 0.2
        root.addChildNode(plaza)
        let centerpiece = Expo3D.cylinder(2.9,9,Expo3D.bronze,sides:6)
        centerpiece.position.y = 4.65
        root.addChildNode(centerpiece)
        let crown = SCNNode(geometry: SCNSphere(radius: 2.8))
        crown.geometry?.firstMaterial = Expo3D.ivory
        crown.position.y = 10
        root.addChildNode(crown)

        // Crucial: the actual navigation graph is also the geometry source for visible paths.
        for edge in graph.edges {
            guard let a = graph.nodes[edge.from]?.position.point,
                  let b = graph.nodes[edge.to]?.position.point else { continue }
            let a3 = Expo3D.world(a, height: 0.18)
            let b3 = Expo3D.world(b, height: 0.18)
            let width: CGFloat = edge.to.hasPrefix("location/") || edge.from.hasPrefix("location/") ? 2.15 : 3.6
            root.addChildNode(Expo3D.segment(a3,b3,diameter:width+0.9,material:Expo3D.pathBorder))
            root.addChildNode(Expo3D.segment(SCNVector3(a3.x,0.33,a3.z),
                                             SCNVector3(b3.x,0.33,b3.z),diameter:width,material:Expo3D.paths))
        }
        // Regular, seeded planted islands outside the graph and the pavilion footprints.
        let buildings = dataset.map.locations.compactMap { location -> ExpoNavPoint? in
            guard let p = graph.nodes["location/\(location.id)"]?.position.point else { return nil }
            return buildingCenter(for:location,door:p)
        }
        for index in 0..<140 {
            let angle = Double(index) * 2.399963229728653
            let r = 76 + sqrt(Double(index)/140)*290
            let p = ExpoNavPoint(500 + cos(angle)*r,350 + sin(angle)*r)
            let pathGap = graph.edges.contains { e in
                guard let a = graph.nodes[e.from]?.position.point,let b = graph.nodes[e.to]?.position.point else { return false }
                let d = b.x-a.x, dy = b.y-a.y, l2 = d*d+dy*dy
                let t = l2 == 0 ? 0 : max(0,min(1,((p.x-a.x)*d+(p.y-a.y)*dy)/l2))
                return p.distance(to:a.interpolated(to:b,fraction:t)) < 9
            }
            if pathGap || buildings.contains(where: { $0.distance(to:p) < 31 }) { continue }
            let v = Expo3D.world(p)
            let tree = SCNNode()
            let trunk = Expo3D.cylinder(0.36,3.0,Expo3D.bronze, sides:6)
            trunk.position.y = 1.5; tree.addChildNode(trunk)
            let leaves = SCNNode(geometry: SCNSphere(radius: 2.2 + CGFloat(index % 4) * 0.23))
            leaves.geometry?.firstMaterial = index%3 == 0 ? Expo3D.paleGreen : Expo3D.foliage
            leaves.position.y = 4; tree.addChildNode(leaves)
            tree.position = v
            root.addChildNode(tree)
        }
        for location in dataset.map.locations {
            guard let entrance = graph.nodes["location/\(location.id)"]?.position.point else { continue }
            let p = buildingCenter(for:location,door:entrance)
            root.addChildNode(makeBuilding(location, at:p))
        }
        let selection = SCNNode(geometry: SCNTorus(ringRadius:3.3,pipeRadius:0.55))
        selection.geometry?.firstMaterial = Expo3D.blue
        selection.isHidden = true
        coordinator.selection = selection
        root.addChildNode(selection)
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 49
        cameraNode.camera?.zNear = 0.5
        cameraNode.camera?.zFar = 500
        cameraNode.position = SCNVector3(95,116,120)
        cameraNode.look(at: SCNVector3(0,0,0))
        root.addChildNode(cameraNode)
        coordinator.camera = cameraNode
        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.color = UIColor(hexString:"#E4F0EF")
        ambient.light?.intensity = 720
        root.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight(); sun.light?.type = .directional
        sun.light?.intensity = 1050
        sun.light?.castsShadow = false
        sun.position = SCNVector3(-75,140,90)
        sun.look(at: SCNVector3(0,0,0))
        root.addChildNode(sun)
        return scene
    }
    private func buildingCenter(for location:ExpoLocation,door:ExpoNavPoint) -> ExpoNavPoint {
        OutdoorGeometry.buildingCenter(location,door:door)
    }
    private func makeBuilding(_ location:ExpoLocation,at point:ExpoNavPoint) -> SCNNode {
        let group = SCNNode()
        group.name = "location|\(location.id)"
        group.position = Expo3D.world(point)
        if let door = store.outdoor.nodes["location/\(location.id)"]?.position.point {
            group.eulerAngles.y = Float(atan2(door.x-point.x, door.y-point.y))
        }
        let name = location.id
        if name == "hub" { return group }
        if name.hasPrefix("gate") {
            let podium=Expo3D.cylinder(3.3,0.8,Expo3D.ivory)
            podium.position.y=0.7;group.addChildNode(podium)
            for offset: Float in [-3.1,3.1] {
                group.addChildNode(Expo3D.box(0.8,7,0.85,Expo3D.bronze,x:offset,y:4,z:0))
            }
            group.addChildNode(Expo3D.box(8,1.4,1.8,Expo3D.ivory,y:8))
            let label = SCNNode(geometry: SCNText(string:String(name.last ?? "?"),extrusionDepth:0.15))
            label.geometry?.firstMaterial = Expo3D.forest
            label.scale=SCNVector3(0.07,0.07,0.07)
            label.position=SCNVector3(-1,8.5,1)
            group.addChildNode(label)
            return group
        }
        if name == "garden" {
            let island=Expo3D.cylinder(4.9,1,Expo3D.paleGreen)
            island.position.y=0.3;group.addChildNode(island)
            return group
        }
        let isPavilion = location.kind == "pavilion"
        let isSaudi = name == "sa"
        let size: CGFloat = isSaudi ? 12.0 : location.size == "lg" ? 9.2 : isPavilion ? 8.0 : 5.0
        let height: CGFloat = isSaudi ? 12 : isPavilion ? 8 : 4.5
        group.addChildNode(Expo3D.box(size+2.1,0.85,size+1.5,Expo3D.ivory,y:0.45))
        let base = Expo3D.box(size,height*0.76,size*0.82, isSaudi ? Expo3D.sand : Expo3D.glass, y:Float(height*0.38+1))
        group.addChildNode(base)
        for side in [-1.0,1.0] {
            group.addChildNode(Expo3D.box(0.3,height*0.7,size*0.86,Expo3D.ivory,
                                          x:Float(side*Double(size)*0.46),y:Float(height*0.38+1)))
        }
        let variants=["sa","jp","kr","sg","ae","de","fr","it","cn","uk","us","eg"]
        let variant = variants.firstIndex(of:name) ?? 0
        switch variant % 4 {
        case 0:
            let roof = Expo3D.cylinder(size*0.63,2.1, isSaudi ? Expo3D.bronze : Expo3D.ivory, sides:6)
            roof.position.y = Float(height*0.77+2)
            group.addChildNode(roof)
            let canopy = Expo3D.cylinder(size*0.40,1.2,Expo3D.ivory,sides:6)
            canopy.position.y=Float(height*0.77+3.6)
            group.addChildNode(canopy)
        case 1:
            let roof = Expo3D.box(size+2,1.1,size+2,Expo3D.ivory,y:Float(height*0.76+1.6))
            group.addChildNode(roof)
            for i in 0..<5 {
                group.addChildNode(Expo3D.box(0.55,1.3,size*0.87,Expo3D.bronze,
                                              x:Float(CGFloat(i-2)*size/6),y:Float(height*0.76+2.7)))
            }
        case 2:
            let cylinder=Expo3D.cylinder(size*0.52,2.1,Expo3D.material("#DDE5D9"),sides:8)
            cylinder.position.y=Float(height*0.76+2);group.addChildNode(cylinder)
            let roof=SCNNode(geometry:SCNCone(topRadius:0,bottomRadius:size*0.53,height:3.5))
            roof.geometry?.firstMaterial=Expo3D.ivory
            roof.position.y=Float(height*0.76+4.1);group.addChildNode(roof)
        default:
            for tier in 0..<3 {
                group.addChildNode(Expo3D.box(size+0.5-CGFloat(tier),0.8,size+0.5-CGFloat(tier),
                                              tier%2==0 ? Expo3D.ivory : Expo3D.sand,
                                              y:Float(height*0.76+1.9+CGFloat(tier))))
            }
        }
        for i in -2...2 {
            let beam=Expo3D.box(0.19,height*0.61,0.28, isSaudi ? Expo3D.bronze : Expo3D.ivory,
                                x:Float(CGFloat(i)*size/7),y:Float(height*0.36+1.2),z:Float(size*0.42))
            group.addChildNode(beam)
        }
        let entrance = Expo3D.box(size*0.28,height*0.38,0.24,Expo3D.darkGlass,
                                  y:Float(height*0.19+0.85),z:Float(size*0.43))
        group.addChildNode(entrance)
        return group
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var store: ExpoStore
        weak var view: SCNView?
        var selection=SCNNode()
        var camera=SCNNode()
        var lastSelection: String?
        var lastCameraRevision = -1
        init(store:ExpoStore) { self.store=store }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func didTap(_ sender: UITapGestureRecognizer) {
            guard let view else { return }
            let p=sender.location(in:view)
            let hits=view.hitTest(p,options:[SCNHitTestOption.firstFoundOnly:false])
            for hit in hits {
                var node: SCNNode? = hit.node
                while let current=node {
                    if let name=current.name,name.hasPrefix("location|") {
                        store.selectLocation(String(name.dropFirst("location|".count)))
                        return
                    }
                    node=current.parent
                }
            }
            // Exterior gestures never reposition a simulated visitor.
        }
    }
}
