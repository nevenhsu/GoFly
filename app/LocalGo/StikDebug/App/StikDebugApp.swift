//
//  StikDebugApp.swift
//  StikDebug
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI

@main
struct StikDebugApp: App {
    @StateObject private var features = LocalGoFeatureModel()
    init() {
        AppBootstrapper.configure()
    }

    var body: some Scene {
        WindowGroup {
            LocalGoMapView(model: features)
        }
    }

}
