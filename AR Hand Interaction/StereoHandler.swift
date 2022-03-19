//
//  StereoHandler.swift
//  AR Hand Interaction
//
//  Created by Bidipta Sarkar on 2/18/22.
//

// Code adapted from https://github.com/hanleyweng/iOS-ARKit-Headset-View/blob/master/ARKit%20Headset%20View/ARSCNStereoViewClass_v4.swift

import Foundation
import SceneKit
import ARKit

class ARSCNStereoView {
    let isDebug = true
    
    var sceneView: ARSCNView!
    var sceneViewLeft: ARSCNView!
    var sceneViewRight: ARSCNView!
    
    var scene: SCNScene {
        get {
            return sceneView.scene
        }
        set(newscene) {
            sceneView.scene = newscene
            sceneViewLeft.scene = newscene
            sceneViewRight.scene = newscene
        }
    }
        
    let eyeCamera : SCNCamera = SCNCamera()
    
    // Parametres
    let _CAMERA_IS_ON_LEFT_EYE = true
    let interpupilaryDistance : Float = 0.066 // This is the value for the distance between two pupils (in metres). The Interpupilary Distance (IPD).
    
    /*
     SET eyeFOV and cameraImageScale. UNCOMMENT any of the below lines to change FOV:
     */
    //    let eyeFOV = 38.5; var cameraImageScale = 1.739; // (FOV: 38.5 ± 2.0) Brute-force estimate based on iPhone7+
    let eyeFOV = 60; var cameraImageScale = 3.478; // Calculation based on iPhone7+ // <- Works ok for cheap mobile headsets. Rough guestimate.
    //    let eyeFOV = 90; var cameraImageScale = 6; // (Scale: 6 ± 1.0) Very Rough Guestimate.
    //    let eyeFOV = 120; var cameraImageScale = 8.756; // Rough Guestimate.
    
    func viewDidLoad_setup(iSceneView: ARSCNView, iSceneViewLeft: ARSCNView, iSceneViewRight: ARSCNView) {
        
        sceneView = iSceneView
        sceneViewLeft = iSceneViewLeft
        sceneViewRight = iSceneViewRight
        
        sceneViewLeft.session = sceneView.session
        sceneViewRight.session = sceneView.session
                
        ////////////////////////////////////////////////////////////////
        // Prevent Auto-Lock
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Prevent Screen Dimming
        let currentScreenBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = currentScreenBrightness
        
        ////////////////////////////////////////////////////////////////
        // Show statistics such as fps and timing information
        if (isDebug) {
            sceneView.showsStatistics = true
        }
        
        ////////////////////////////////////////////////////////////////
        // Set Debug Options
//        sceneView.debugOptions = [ARSCNDebugOptions.showWorldOrigin, .showFeaturePoints]
        
        // Scene setup
        sceneView.isHidden = true
        
        ////////////////////////////////////////////////////////////////
        // Set up Left-Eye SceneView
        sceneViewLeft.scene = sceneView.scene
        sceneViewLeft.showsStatistics = sceneView.showsStatistics
        sceneViewLeft.isPlaying = true
        
        // Set up Right-Eye SceneView
        sceneViewRight.scene = sceneView.scene
        sceneViewRight.showsStatistics = sceneView.showsStatistics
        sceneViewRight.isPlaying = true
        
        cameraImageScale = cameraImageScale * 1080.0 / 720.0
        
        ////////////////////////////////////////////////////////////////
        // Create CAMERA
        eyeCamera.zNear = 0.001
        eyeCamera.fieldOfView = CGFloat(eyeFOV)
    }
    
    /* Called constantly, at every Frame */
    func updateFrame() {
//        updatePOVs()
    }
    
    func updatePOVs() {
        /////////////////////////////////////////////
        // CREATE POINT OF VIEWS
        let pointOfView : SCNNode = SCNNode()
        pointOfView.transform = (sceneView.pointOfView?.transform)!
        pointOfView.camera = eyeCamera
        sceneViewLeft.pointOfView = pointOfView

        // Clone pointOfView for Right-Eye SceneView
        let pointOfView2 : SCNNode = pointOfView.clone()
        
        // Determine Adjusted Position for Right Eye
        
        // Get original orientation. Co-ordinates:
        let orientation : SCNQuaternion = pointOfView2.orientation // not '.worldOrientation'
        let orientation_glk : GLKQuaternion = GLKQuaternionMake(orientation.x, orientation.y, orientation.z, orientation.w)
        let alternateEyePos : GLKVector3 = GLKVector3Make(1, 0.0, 0.0)
        let transformVector = getTransformForNewNodePovPosition(orientationQuaternion: orientation_glk, eyePosDirection: alternateEyePos, magnitude: interpupilaryDistance)
        
        // Add Transform to PointOfView2
        pointOfView2.position = SCNVector3Make(pointOfView2.position.x + transformVector.x,
                                               pointOfView2.position.y + transformVector.y,
                                               pointOfView2.position.z + transformVector.z)

        // Set PointOfView2 for SceneView-RightEye
        sceneViewRight.pointOfView = pointOfView2
    }
    
    /**
     Used by POVs to ensure correct POVs.
     
     For EyePosVector e.g. This would be GLKVector3Make(- 1.0, 0.0, 0.0) if we were manipulating an eye to the 'left' of the source-View. Or, in the odd case we were manipulating an eye that was 'above' the eye of the source-view, it'd be GLKVector3Make(0.0, 1.0, 0.0).
     */
    private func getTransformForNewNodePovPosition(orientationQuaternion: GLKQuaternion, eyePosDirection: GLKVector3, magnitude: Float) -> SCNVector3 {
        // Rotate POV's-Orientation-Quaternion around Vector-to-EyePos.
        let rotatedEyePos : GLKVector3 = GLKQuaternionRotateVector3(orientationQuaternion, eyePosDirection)
        
        // Multiply Vector by magnitude (interpupilary distance)
        let transformVector : SCNVector3 = SCNVector3Make(rotatedEyePos.x * magnitude,
                                                          rotatedEyePos.y * magnitude,
                                                          rotatedEyePos.z * magnitude)
        return transformVector
        
    }
    
}
