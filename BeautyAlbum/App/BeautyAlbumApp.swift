import SwiftUI

@main
struct BeautyAlbumApp: App {
    @StateObject private var store = Store.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.light)
                .tint(Theme.roseDeep)
        }
    }
}
