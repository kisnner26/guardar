import SwiftUI
import WebKit

/// sesion de instagram del propio usuario. las cookies viven en el almacen de WKWebView
/// de la app y solo se usan para pedir los reels que esa cuenta ya puede ver.
@MainActor
enum IGSession {
    static func cookies() async -> [HTTPCookie] {
        let all = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return all.filter { $0.domain.contains("instagram.com") }
    }

    static func isLoggedIn() async -> Bool {
        await cookies().contains { $0.name == "sessionid" && !$0.value.isEmpty }
    }

    /// copia las cookies al almacen de URLSession para poder usarlas en las peticiones
    static func syncToURLSession() async {
        for c in await cookies() { HTTPCookieStorage.shared.setCookie(c) }
    }

    static func logout() async {
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                               for: records.filter { $0.displayName.contains("instagram") })
        for c in HTTPCookieStorage.shared.cookies ?? [] where c.domain.contains("instagram.com") {
            HTTPCookieStorage.shared.deleteCookie(c)
        }
    }
}

struct IGLoginView: View {
    @Environment(\.dismiss) private var dismiss
    var onLoggedIn: () -> Void

    var body: some View {
        NavigationStack {
            WebLogin(onLoggedIn: { onLoggedIn(); dismiss() })
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("instagram").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("cerrar") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct WebLogin: UIViewRepresentable {
    var onLoggedIn: () -> Void

    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.load(URLRequest(url: URL(string: "https://www.instagram.com/accounts/login/")!))
        context.coordinator.start(w)
        return w
    }
    func updateUIView(_ v: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onLoggedIn) }

    final class Coordinator {
        let onLoggedIn: () -> Void
        var timer: Timer?
        init(_ f: @escaping () -> Void) { onLoggedIn = f }
        func start(_ w: WKWebView) {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                Task { @MainActor in
                    if await IGSession.isLoggedIn() { t.invalidate(); self?.onLoggedIn() }
                }
            }
        }
        deinit { timer?.invalidate() }
    }
}
