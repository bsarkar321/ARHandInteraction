//
//  ViewController.swift
//  AR Hand Interaction
//
//  Created by Bidipta Sarkar on 2/18/22.
//

import UIKit
import SceneKit
import ARKit
import MultipeerConnectivity
import Vision
import AVFoundation

let USE_DEPTH = false
let TIME_OUT = 100

class ViewController: UIViewController, ARSCNViewDelegate, ARSessionDelegate {
    // Stereo Viewers
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var sceneViewLeft: ARSCNView!
    @IBOutlet weak var sceneViewRight: ARSCNView!
    @IBOutlet weak var messageLabel: MessageLabel!
    
//    var previewView = UIImageView()
    
    let scnStereoView = ARSCNStereoView()
    let viewBackgroundColor: UIColor = UIColor.black
    
    
    // Multipeer connectivity
    
    var multipeerSession: MultipeerSession!
    
    var peerSessionIDs = [MCPeerID: String]()
    
    var sessionIDObservation: NSKeyValueObservation?
    
    var configuration: ARWorldTrackingConfiguration?
    
    var participantAnchors = [SCNNode]()
    
    
    // Hand Detection
    var currentBuffer: CVPixelBuffer?
    var handPoseRequest = VNDetectHumanHandPoseRequest()
    let visionQueue = DispatchQueue(label: "handVisionQueue")
    
    var lefthandnode: HandNode?
    var righthandnode: HandNode?
    
    var timeoutleft = TIME_OUT
    var timeoutright = TIME_OUT
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Set the view's delegate
        sceneView.delegate = self
        
        sceneView.session.delegate = self
                
        // Show statistics such as fps and timing information
        sceneView.showsStatistics = true
        
        // stereoview setup
        scnStereoView.viewDidLoad_setup(iSceneView: sceneView, iSceneViewLeft: sceneViewLeft, iSceneViewRight: sceneViewRight)
        self.view.backgroundColor = viewBackgroundColor
        
        // Prevents phone from going to sleep
        UIApplication.shared.isIdleTimerDisabled = true
        
        configuration = ARWorldTrackingConfiguration()
        
        configuration!.planeDetection = .horizontal
        
        if USE_DEPTH && ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration?.frameSemantics.insert(.personSegmentationWithDepth)
        } else {
            print("No people occlusion supported.")
        }
        
        configuration?.isCollaborationEnabled = true
        
        configuration?.environmentTexturing = .automatic
        
        sceneView.session.run(configuration!)
        
        // Use key-value observation to monitor your ARSession's identifier.
        sessionIDObservation = observe(\.sceneView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            // Tell all other peers about your ARSession's changed ID, so
            // that they can keep track of which ARAnchors are yours.
            guard let multipeerSession = self.multipeerSession else { return }
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        // Start looking for other players via MultiPeerConnectivity.
        multipeerSession = MultipeerSession(receivedDataHandler: receivedData, peerJoinedHandler:
                                            peerJoined, peerLeftHandler: peerLeft, peerDiscoveredHandler: peerDiscovered)
        messageLabel.displayMessage("Invite others to launch this app to join you.", duration: 60.0)
        
        // Handle hand pose requests
        handPoseRequest.maximumHandCount = 2
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        self.currentBuffer = frame.capturedImage
        classifyHand()
    }
    
    func classifyHand() {
        var templefthandobs: VNHumanHandPoseObservation?
        var temprighthandobs: VNHumanHandPoseObservation?
        let handler = VNImageRequestHandler(cvPixelBuffer: currentBuffer!, orientation: .left)
        
//        self.previewView.image = UIImage(ciImage: CIImage(cvPixelBuffer: self.sceneView.session.currentFrame!.estimatedDepthData!))
        visionQueue.async {
            do {
                defer {
                    self.currentBuffer = nil
                    
                    self.processPoints(newhandobs: templefthandobs, handnode: &self.lefthandnode, timeout: &self.timeoutleft, color: UIColor.blue)
                    self.processPoints(newhandobs: temprighthandobs, handnode: &self.righthandnode, timeout: &self.timeoutright, color: UIColor.green)
                }
                
                try handler.perform([self.handPoseRequest])
                guard let obs1 = self.handPoseRequest.results?.first else {
                    return
                }
                
                if obs1.chirality == .left {
                    templefthandobs = obs1
                } else {
                    temprighthandobs = obs1
                }
                
                if self.handPoseRequest.results?.count == 1 {
                    return
                }
                
                guard let obs2 = self.handPoseRequest.results?[1] else {
                    return
                }
                
                if obs1.chirality == .right {
                    templefthandobs = obs2
                } else {
                    temprighthandobs = obs2
                }
                
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
        
    }
    
    func processPoints(newhandobs: VNHumanHandPoseObservation?, handnode: inout HandNode?, timeout: inout Int, color: UIColor) {
        if newhandobs != nil {
            if handnode == nil {
                handnode = HandNode(color: color)
            }
            
            if handnode!.parent == nil {
                self.sceneView.scene.rootNode.addChildNode(handnode!)
            }
            let (newconst, untransconst) = handnode!.createConstraints(pose: newhandobs!, camera: sceneView.session.currentFrame!.camera)
            handnode!.addConstraint(peerID: "", constraints: newconst)
            handnode!.applyConstraints()
            
            if let archivedData = try? NSKeyedArchiver.archivedData(withRootObject: HandConstraints(const: untransconst), requiringSecureCoding: true) {
                multipeerSession.sendToAllPeers(archivedData, reliably: true)
            }
            
            timeout = TIME_OUT
        } else if handnode != nil {
            if timeout > 0 {
                timeout -= 1
            } else {
                handnode!.removeFromParentNode()
            }
        }
    }
    
//    func processPoints(newlefthandobs: VNHumanHandPoseObservation?, newrighthandobs: VNHumanHandPoseObservation?) {
//        if newlefthandobs != nil {
//            if lefthandnode == nil {
//                lefthandnode = HandNode()
//            }
//
//            if lefthandnode!.parent == nil {
//                self.sceneView.scene.rootNode.addChildNode(lefthandnode!)
//            }
//            lefthandnode!.updatepose(pose: newlefthandobs!, camera: sceneView.session.currentFrame!.camera, sceneview: sceneView)
//            timeoutleft = TIME_OUT
//        } else if lefthandnode != nil {
//            if timeoutleft > 0 {
//                timeoutleft -= 1
//            } else {
//                lefthandnode!.removeFromParentNode()
//            }
//        }
//
//        if newrighthandobs != nil {
//            if righthandnode == nil {
//                righthandnode = HandNode()
//            }
//
//            if righthandnode!.parent == nil {
//                self.sceneView.scene.rootNode.addChildNode(righthandnode!)
//            }
//            righthandnode!.updatepose(pose: newrighthandobs!, camera: sceneView.session.currentFrame!.camera, sceneview: sceneView)
//            timeoutright = TIME_OUT
//        } else if righthandnode != nil {
//            if timeoutright > 0 {
//                timeoutright -= 1
//            } else {
//                righthandnode!.removeFromParentNode()
//            }
//        }
//    }
    
//    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
//        for anchor in anchors {
//            if let participantAnchor = anchor as? ARParticipantAnchor {
//                print("WOWSER")
//                messageLabel.displayMessage("Established joint experience with a peer.")
//                sceneView.session.add(anchor: participantAnchor)
//                let anchorEntity = sceneView.node(for: participantAnchor)
//
//                let color = participantAnchor.sessionIdentifier?.toRandomColor() ?? .white
//
//                let coloredSphere = SCNSphere(radius: 0.03)
//                coloredSphere.materials = [SCNMaterial()]
//                coloredSphere.firstMaterial?.diffuse.contents = color
//
//                anchorEntity?.addChildNode(SCNNode(geometry: coloredSphere))
//
//                sceneView.scene.rootNode.addChildNode(anchorEntity!)
//
//            } else if anchor.name == "Anchor for object placement" {
//                // Create a cube at the location of the anchor.
//                let boxLength: CGFloat = 0.05
//                // Color the cube based on the user that placed it.
//                let color = anchor.sessionIdentifier?.toRandomColor() ?? .white
//
//                let coloredCube = SCNBox(width: boxLength, height: boxLength, length: boxLength, chamferRadius: 0)
//                coloredCube.materials = [SCNMaterial()]
//                coloredCube.firstMaterial?.diffuse.contents = color
//
//                let cubeNode = SCNNode(geometry: coloredCube)
//                // Offset the cube by half its length to align its bottom with the real-world surface.
//                cubeNode.position = SCNVector3Make(0, Float(boxLength) / 2, 0)
//
//                // Attach the cube to the ARAnchor via an AnchorEntity.
//                //   World origin -> ARAnchor -> AnchorEntity -> ModelEntity
//                sceneView.session.add(anchor: anchor)
//                let anchorEntity = sceneView.node(for: anchor)
//                anchorEntity?.addChildNode(cubeNode)
//                sceneView.scene.rootNode.addChildNode(anchorEntity!)
//            }
//        }
//    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        if let participantAnchor = anchor as? ARParticipantAnchor {
            print("GOT EXPERIENCE")
            messageLabel.displayMessage("Established joint experience with a peer.")
            sceneView.session.add(anchor: participantAnchor)
            let anchorEntity = node
                        
            let color = participantAnchor.sessionIdentifier?.toRandomColor() ?? .white
            
            let coloredSphere = SCNSphere(radius: 0.03)
            coloredSphere.materials = [SCNMaterial()]
            coloredSphere.firstMaterial?.diffuse.contents = color
            
            let sphereNode = SCNNode(geometry: coloredSphere)
            
            if (UIDevice.current.model == "iPhone") {
                sphereNode.position = SCNVector3Make(-0.15, 0.1, 0)
            }
            
            anchorEntity.addChildNode(sphereNode)
            
            sceneView.scene.rootNode.addChildNode(anchorEntity)
            
            participantAnchors.append(sphereNode)
            
        } else if anchor.name == "Anchor for object placement" {
            // Create a cube at the location of the anchor.
            let boxLength: CGFloat = 0.05
            // Color the cube based on the user that placed it.
            let color = anchor.sessionIdentifier?.toRandomColor() ?? .white
            
            let coloredCube = SCNBox(width: boxLength, height: boxLength, length: boxLength, chamferRadius: 0)
            coloredCube.materials = [SCNMaterial()]
            coloredCube.firstMaterial?.diffuse.contents = color
            
            let cubeNode = SCNNode(geometry: coloredCube)
            // Offset the cube by half its length to align its bottom with the real-world surface.
            cubeNode.position = SCNVector3Make(0, Float(boxLength) / 2, 0)
            
            // Attach the cube to the ARAnchor via an AnchorEntity.
            //   World origin -> ARAnchor -> AnchorEntity -> ModelEntity
            sceneView.session.add(anchor: anchor)
            let anchorEntity = node
            anchorEntity.addChildNode(cubeNode)
            sceneView.scene.rootNode.addChildNode(anchorEntity)
        }
    }
    
    /// - Tag: DidOutputCollaborationData
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let multipeerSession = multipeerSession else { return }
        if !multipeerSession.connectedPeers.isEmpty {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            else { fatalError("Unexpectedly failed to encode collaboration data.") }
            // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
        } else {
//            print("Deferred sending collaboration to later because there are no peers.")
        }
    }

    func receivedData(_ data: Data, from peer: MCPeerID) {
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            sceneView.session.update(with: collaborationData)
            return
        }
        
        if let handData = (try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [HandConstraints.self, NSNumber.self], from: data)) as? HandConstraints {
            if lefthandnode == nil && righthandnode == nil {
                return
            }
            if righthandnode == nil {
                lefthandnode!.addConstraint(peerID: "1", constraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform)
                return
            } else if lefthandnode == nil {
                righthandnode!.addConstraint(peerID: "1", constraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform)
                return
            }
            
            if lefthandnode!.getExistingCompatibility(newConstraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform) < righthandnode!.getExistingCompatibility(newConstraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform) {
                lefthandnode!.addConstraint(peerID: "1", constraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform)
            } else {
                righthandnode!.addConstraint(peerID: "1", constraints: handData.trueConstraints, transform: participantAnchors.last!.simdWorldTransform)
            }
            return
        }
        
        // ...
        let sessionIDCommandString = "SessionID:"
        if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex,
                                                                     offsetBy: sessionIDCommandString.count)...])
            // If this peer was using a different session ID before, remove all its associated anchors.
            // This will remove the old participant anchor and its geometry from the scene.
            if let oldSessionID = peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            peerSessionIDs[peer] = newSessionID
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        DispatchQueue.main.async {
            // Present the error that occurred.
            let alertController = UIAlertController(title: "The AR session failed.", message: errorMessage, preferredStyle: .alert)
            let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
                alertController.dismiss(animated: true, completion: nil)
                self.resetTracking()
            }
            alertController.addAction(restartAction)
            self.present(alertController, animated: true, completion: nil)
        }
    }
    
    func resetTracking() {
        guard let configuration = sceneView.session.configuration else { print("A configuration is required"); return }
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - ARSCNViewDelegate
    

    // Override to create and configure nodes for anchors added to the view's session.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async{
            self.scnStereoView.updateFrame()
        }
    }
    
//    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
//        return SCNNode(geometry: SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0))
//    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    func peerDiscovered(_ peer: MCPeerID) -> Bool {
        return true
    }
    /// - Tag: PeerJoined
    func peerJoined(_ peer: MCPeerID) {
        messageLabel.displayMessage("""
            A peer wants to join the experience.
            Hold the phones next to each other.
            """, duration: 6.0)
        
        sendARSessionIDTo(peers: [peer])
    }
        
    func peerLeft(_ peer: MCPeerID) {
        messageLabel.displayMessage("A peer has left the shared experience.")
        
        // Remove all ARAnchors associated with the peer that just left the experience.
        if let sessionID = peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            peerSessionIDs.removeValue(forKey: peer)
        }
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = sceneView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                sceneView.session.remove(anchor: anchor)
            }
        }
    }
    
    private func sendARSessionIDTo(peers: [MCPeerID]) {
        guard let multipeerSession = multipeerSession else { return }
        let idString = sceneView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
}
