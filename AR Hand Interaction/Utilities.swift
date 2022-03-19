//
//  Utilities.swift
//  AR Hand Interaction
//
//  Created by Bidipta Sarkar on 2/19/22.
//

import Foundation
import ARKit

extension UUID {
    /**
     - Tag: ToRandomColor
    Pseudo-randomly return one of several fixed standard colors, based on this UUID's first four bytes.
    */
    func toRandomColor() -> UIColor {
        var firstFourUUIDBytesAsUInt32: UInt32 = 0
        let data = withUnsafePointer(to: self) {
            return Data(bytes: $0, count: MemoryLayout.size(ofValue: self))
        }
        _ = withUnsafeMutableBytes(of: &firstFourUUIDBytesAsUInt32, { data.copyBytes(to: $0) })

        let colors: [UIColor] = [.red, .green, .blue, .yellow, .magenta, .cyan, .purple,
        .orange, .brown, .lightGray, .gray, .darkGray, .black, .white]
        
        let randomNumber = Int(firstFourUUIDBytesAsUInt32) % colors.count
        return colors[randomNumber]
    }
}
