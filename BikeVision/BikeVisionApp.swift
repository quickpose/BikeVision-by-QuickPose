//
//  BikeVisionApp.swift
//  BikeVision
//
//  Created by Filip Ljubicic on 12/03/2026.
//

import SwiftUI
import CoreData

@main
struct BikeVisionApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
