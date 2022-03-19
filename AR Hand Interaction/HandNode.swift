//
//  HandNode.swift
//  AR Hand Interaction
//
//  Created by Bidipta Sarkar on 2/20/22.
//

import Foundation
import SceneKit
import ARKit
import Vision

class HandNode: SCNNode {
    
    let validKeys: [VNHumanHandPoseObservation.JointName] = [.wrist,
                                                             .thumbTip, .thumbIP, .thumbMP, .thumbCMC,
                                                             .indexTip, .indexDIP, .indexPIP, .indexMCP,
                                                             .middleTip, .middleDIP, .middlePIP, .middleMCP,
                                                             .ringTip, .ringDIP, .ringPIP, .ringMCP,
                                                             .littleTip, .littleDIP, .littlePIP, .littleMCP]
    
    var keyToInd = [VNHumanHandPoseObservation.JointName : Int]()
    var collabConstraints = [String : [simd_float3]]()
    
    var mapping = [VNHumanHandPoseObservation.JointName : SCNNode]()
    
    var measurements = [Float]()
    
    init(color: UIColor) {
        super.init()
        
        for (index, key) in validKeys.enumerated() {
            let node = SCNNode()
            let coloredSphere = SCNSphere(radius: 0.005)
            coloredSphere.materials = [SCNMaterial()]
            coloredSphere.firstMaterial?.diffuse.contents = color
            node.geometry = coloredSphere
            
            self.addChildNode(node)
            mapping[key] = node
            keyToInd[key] = index
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func getDepth(_ loc2d: VNRecognizedPoint, _ width: Int, _ height: Int, _ depthPointer: UnsafeMutablePointer<Float32>) -> Float32 {
        let u0: Double = max(2, min(Double(width) - 3.0, loc2d.y * Double(width)))
        let v0: Double = max(2, min(Double(height) - 3.0, loc2d.x * Double(height)))
        var z: Float = 0.0
        for u in Int(floor(u0)) - 2 ... Int(ceil(u0)) + 2 {
            for v in Int(floor(v0)) - 2 ... Int(ceil(v0)) + 2 {
                let znew = depthPointer[Int(v) * width + Int(u)]
                if znew != 0 {
                    z = max(znew, z)
                }
            }
        }
        return z
    }
    
    func dist2(_ p1: SCNVector3, _ p2: SCNVector3) -> Float {
        return pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2) + pow(p1.z - p2.z, 2)
    }
    
    func createConstraints(pose: VNHumanHandPoseObservation, camera: ARCamera) -> ([simd_float3], [simd_float3]) {
        var untransformedConstraints = [simd_float3](repeating: simd_float3(0, 0, 0), count: validKeys.count)
        
        var fullConstraints = [simd_float3](repeating: simd_float3(0, 0, 0), count: validKeys.count + 1)
        let M = camera.transform
        let ratio = Float(camera.imageResolution.width / camera.imageResolution.height)
        fullConstraints[0] = simd_make_float3(simd_mul(M, simd_float4(0, 0, 0, 1)))
        
        for joint in pose.availableJointNames {
            guard let loc2d = try? pose.recognizedPoint(joint) else {
                continue
            }
            if let ind = keyToInd[joint] {
                let normcoord = simd_float4(ratio * Float(loc2d.y - 0.5), -Float(loc2d.x - 0.5), -1.0, 0)
                let hpos = simd_make_float3(simd_mul(M, normcoord))
                fullConstraints[ind + 1] = simd_normalize(hpos)
                untransformedConstraints[ind] = simd_make_float3(normcoord)
            }
        }
        return (fullConstraints, untransformedConstraints)
    }
    
    func addConstraint(peerID: String, constraints: [simd_float3]) {
        collabConstraints[peerID] = constraints
    }
    
    func addConstraint(peerID: String, constraints: [simd_float3], transform: simd_float4x4) {
        var fullConstraints = [simd_float3](repeating: simd_float3(0, 0, 0), count: validKeys.count + 1)
        
        fullConstraints[0] = simd_make_float3(simd_mul(transform, simd_float4(0, 0, 0, 1)))
        
        for (ind, vec) in constraints.enumerated() {
            let normcoord = simd_make_float4(vec, 0)
            let hpos = simd_make_float3(simd_mul(transform, normcoord))
            fullConstraints[ind + 1] = simd_normalize(hpos)
        }
        
        collabConstraints[peerID] = fullConstraints
    }
    
    func applyConstraints() {
        let onlyConstraints = collabConstraints.values
        if onlyConstraints.isEmpty {
            print("NO CONSTRAINTS TO APPLY: SKIPPING")
            return
        }
        
        if (collabConstraints.count == 1) {
            let firstConstraint = onlyConstraints.first!
            
            for (index, key) in validKeys.enumerated() {
                if let node = mapping[key] {
                    let z: Float = 0.5
                    
                    let newloc = firstConstraint[0] + firstConstraint[index + 1] * z
                    node.position = SCNVector3Make(newloc.x, newloc.y, newloc.z)
                }
            }
        } else {
            print("MULTI USER")
            for (index, key) in validKeys.enumerated() {
                if let node = mapping[key] {
                    var A = simd_float3x3(0)
                    var b = simd_float3()
                    for const in onlyConstraints {
                        let a = const[0]
                        let n = const[index + 1]
                        let newmat = simd_float3x3(1) - simd_matrix(n * n[0], n * n[1], n * n[2])
                        A += newmat
                        b += newmat * a
                    }
                    
                    let newloc = simd_mul(simd_mul(A.transpose, A).inverse, simd_mul(A.transpose, b))
                    node.position = SCNVector3Make(newloc.x, newloc.y, newloc.z)
                }
            }
            
            let newDist = sqrt(dist2(mapping[.ringTip]!.position, mapping[.thumbTip]!.position))
//            print("DIST wrist to MCP " + String(newDist))
            measurements.append(newDist)
            print("Mean: " + String(measurements.avg()) + "; STD: " + String(measurements.std()) + "; count: " + String(measurements.count))
            
        }
    }
    
    func getExistingCompatibility(newConstraints: [simd_float3], transform: simd_float4x4) -> Float{
        var fullConstraints = [simd_float3](repeating: simd_float3(0, 0, 0), count: validKeys.count + 1)
        
        fullConstraints[0] = simd_make_float3(simd_mul(transform, simd_float4(0, 0, 0, 1)))
        
        for (ind, vec) in newConstraints.enumerated() {
            let normcoord = simd_make_float4(vec, 0)
            let hpos = simd_make_float3(simd_mul(transform, normcoord))
            fullConstraints[ind + 1] = simd_normalize(hpos)
        }
        
        let testKeys: [VNHumanHandPoseObservation.JointName] = [.wrist]
        
        let tempAllConstraints = [fullConstraints, collabConstraints[""]!]
        
        var squaredError: Float = 0.0
        
        for key in testKeys {
            let index = keyToInd[key]!
            var A = simd_float3x3(0)
            var b = simd_float3()
            for const in tempAllConstraints {
                let a = const[0]
                let n = const[index + 1]
                let newmat = simd_float3x3(1) - simd_matrix(n * n[0], n * n[1], n * n[2])
                A += newmat
                b += newmat * a
            }
            
            let newloc = simd_mul(simd_mul(A.transpose, A).inverse, simd_mul(A.transpose, b))
            
            squaredError += simd_distance(simd_mul(A, newloc), b)
        }
        
        return squaredError
    }
    
//    func updatepose(pose: VNHumanHandPoseObservation, camera: ARCamera, sceneview: ARSCNView) {
////        guard let depthdata = sceneview.session.currentFrame!.estimatedDepthData else {
////            return
////        }
////
////        let width = CVPixelBufferGetWidth(depthdata)
////        let height = CVPixelBufferGetHeight(depthdata)
////
////        CVPixelBufferLockBaseAddress(depthdata, CVPixelBufferLockFlags(rawValue: .zero))
////        let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthdata), to: UnsafeMutablePointer<Float32>.self)
////        print("BEGINNING FRAME")
//        for joint in pose.availableJointNames {
//            guard let loc2d = try? pose.recognizedPoint(joint) else {
//                continue
//            }
//
//            if let node = mapping[joint] {
//                let z: Float = 0.5
////                let z = getDepth(loc2d, width, height, depthPointer)
//                let ratio = Float(camera.imageResolution.width / camera.imageResolution.height)
////                print(z)
//                let normcoord = simd_float4(ratio * Float(loc2d.y - 0.5), -Float(loc2d.x - 0.5), -1.0, 1/z)
//                let hpos = simd_mul(camera.transform, normcoord)
//                node.position = SCNVector3Make(hpos.x / hpos.w, hpos.y / hpos.w, hpos.z / hpos.w)
//            }
//        }
//
////        print("DIST SQUARE wrist to MCP " + String(sqrt(dist2(mapping[.indexMCP]!.position, mapping[.indexPIP]!.position))))
////        print(mapping[.indexMCP]!.position)
//    }
}

class HandConstraints: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool {
        return true
    }
    
    var trueConstraints = [simd_float3]()
    
    func encode(with coder: NSCoder) {
        coder.encode(trueConstraints.count, forKey: "count")
        for val in trueConstraints {
            coder.encode(val[0])
            coder.encode(val[1])
            coder.encode(val[2])
        }
    }
    
    required init?(coder: NSCoder) {
        super.init()
        let counter = coder.decodeInteger(forKey: "count")
        for _ in 0 ..< counter {
            let x = coder.decodeObject() as! Float
            let y = coder.decodeObject() as! Float
            let z = coder.decodeObject() as! Float
            trueConstraints.append(simd_make_float3(x, y, z))
        }
    }
    
    init(const: [simd_float3]) {
        trueConstraints = const
    }
    
    
}

extension Array where Element: FloatingPoint {

    func sum() -> Element {
        return self.reduce(0, +)
    }

    func avg() -> Element {
        return self.sum() / Element(self.count)
    }

    func std() -> Element {
        let mean = self.avg()
        let v = self.reduce(0, { $0 + ($1-mean)*($1-mean) })
        return sqrt(v / (Element(self.count) - 1))
    }

}
