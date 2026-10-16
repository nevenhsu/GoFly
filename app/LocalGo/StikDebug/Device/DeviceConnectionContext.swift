//
//  DeviceConnectionContext.swift
//  StikDebug
//
//  Created by Stephen.
//

import Foundation

enum DeviceConnectionContext {
    static let defaultTargetIPAddress = "10.7.0.1"

    static var targetIPAddress: String {
        // The proof target is this phone through LocalDevVPN only. A mutable
        // endpoint could make identity verification and location writes reach
        // different devices, so the proof build has no remote-IP override.
        defaultTargetIPAddress
    }
}
