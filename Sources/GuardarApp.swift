import SwiftUI

@main
struct GuardarApp: App {
    @State private var showIntro = true
    init() { Ajuste.registrar() }
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView().preferredColorScheme(.dark)
                if showIntro {
                    IntroView().transition(.opacity).zIndex(1)
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.easeInOut(duration: 0.4)) { showIntro = false }
            }
        }
    }
}
