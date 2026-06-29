//
//  BurnrateApp.swift
//  Burnrate
//
//  Created by Nonthawat Kittaywat on 29/6/2569 BE.
//

import SwiftUI

@main
struct BurnrateApp: App {
    // The status bar item, popover, and polling all live in AppDelegate.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No main window — this is a menu-bar-only (agent) app. The settings
        // window is managed directly by AppDelegate, so this scene stays empty.
        Settings {
            EmptyView()
        }
    }
}
