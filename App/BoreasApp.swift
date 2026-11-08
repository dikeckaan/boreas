import ServiceManagement
import SwiftUI

// Temporary scaffold for Task 6: lets the helper be registered by hand. Task 7 replaces it.

@main
struct BoreasApp: App {
    var body: some Scene {
        Window("Boreas", id: "main") {
            PlaceholderView()
        }
    }
}

private struct PlaceholderView: View {
    @State private var status = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Boreas").font(.largeTitle)
            Button("Register helper") {
                do {
                    try SMAppService.daemon(plistName: "com.kaandikec.boreas.helper.plist").register()
                    status = "Registered"
                } catch {
                    status = error.localizedDescription
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 320)
    }
}
