import SwiftUI
import AppKit

@main
struct GestureScrollApp: App {
    @StateObject private var engine = GestureEngine()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 680, minHeight: 820)
        }
        .windowResizability(.contentSize)

        // Menu-bar status icon: shows Off / No hand / Idle / Listening / pinch /
        // firing at a glance, plus a direction arrow when the hand nears the edge.
        MenuBarExtra {
            StatusMenuContent(engine: engine)
        } label: {
            StatusBarLabel(engine: engine)
        }
    }
}

/// The icon shown in the macOS menu bar: a solid color-filled circle (state
/// color) with a white symbol inside. Rendered to a non-template NSImage so the
/// menu bar keeps the real color instead of forcing it to monochrome.
private struct StatusBarLabel: View {
    @ObservedObject var engine: GestureEngine

    var body: some View {
        Image(nsImage: Self.badge(for: engine.status))
    }

    private static func badge(for status: GestureStatus) -> NSImage {
        let renderer = ImageRenderer(content: StatusBadge(status: status, size: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = false   // keep the color; don't let the menu bar tint it
        return image
    }
}

/// The dropdown shown when the menu-bar icon is clicked.
private struct StatusMenuContent: View {
    @ObservedObject var engine: GestureEngine
    @Environment(\.openWindow) private var openWindow

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "GestureScroll \(v)"
    }

    var body: some View {
        // Current state, with the same symbol as the menu-bar icon.
        Label(StatusPresentation.text(engine.status),
              systemImage: StatusPresentation.symbol(engine.status))

        Divider()

        Button(engine.enabled ? "끄기 (Off)" : "켜기 (On)") { engine.toggle() }

        Picker("모드", selection: Binding(get: { engine.mode },
                                         set: { engine.mode = $0 })) {
            ForEach(GestureEngine.ControlMode.allCases) { Text($0.rawValue).tag($0) }
        }

        Divider()

        Button("메인 창 열기") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Toggle("로그인할 때 자동 시작", isOn: Binding(get: { engine.launchAtLogin },
                                                 set: { engine.launchAtLogin = $0 }))

        Divider()

        Text(versionText)

        Button("종료") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
