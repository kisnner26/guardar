import SwiftUI

struct ContentView: View {
    enum Phase: Equatable { case idle, working(String), done(String), failed(String) }

    @State private var text = ""
    @State private var phase: Phase = .idle
    @FocusState private var focused: Bool
    @State private var showLogin = false
    @State private var igLogged = false
    @State private var showSettings = false
    @Environment(\.scenePhase) private var scenePhase

    private let ink = Color(red: 0.96, green: 0.94, blue: 0.89)
    private let accent = Color(red: 1.0, green: 0.36, blue: 0.2)

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("GUARDAR")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(3).foregroundStyle(accent)
                    Spacer()
                    Button { showSettings = true } label: {
                        Text("AJUSTES").font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(2).foregroundStyle(ink.opacity(0.6))
                            .padding(.vertical, 8).padding(.leading, 16)
                    }
                }.padding(.top, 20)
                Text("pega el link.\nse guarda solo.")
                    .font(.system(size: 46, weight: .black, design: .default))
                    .foregroundStyle(ink).lineSpacing(-4)
                    .padding(.top, 14)
                Text("tiktok, instagram reels y x. va directo a fotos, sin pasar por icloud drive.")
                    .font(.system(size: 14)).foregroundStyle(ink.opacity(0.55))
                    .padding(.top, 12)

                Spacer(minLength: 24)

                TextField("", text: $text, prompt: Text("tiktok, instagram o x").foregroundColor(ink.opacity(0.3)), axis: .vertical)
                    .lineLimit(1...3)
                    .font(.system(size: 15, design: .monospaced)).foregroundStyle(ink)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focused)
                    .padding(16)
                    .overlay(Rectangle().stroke(ink.opacity(0.25), lineWidth: 1))
                    .submitLabel(.go).onSubmit(start)

                HStack(spacing: 10) {
                    Button(action: paste) { label("pegar", filled: false) }
                    Button(action: start) { label(isWorking ? "descargando" : "descargar", filled: true) }
                        .disabled(isWorking || text.isEmpty)
                }
                .padding(.top, 10)

                Button(action: igButton) {
                    Text((igLogged ? "instagram conectado  /  salir" : "iniciar sesion en instagram").uppercased())
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).tracking(1.2)
                        .foregroundStyle(igLogged ? accent : ink.opacity(0.45))
                }
                .padding(.top, 16)

                status.padding(.top, 22).frame(minHeight: 56, alignment: .topLeading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
        }
        .onChange(of: scenePhase) { _, p in if p == .active { grabClipboardIfLink() } }
        .onAppear { grabClipboardIfLink(); Task { igLogged = await IGSession.isLoggedIn() } }
        .sheet(isPresented: $showSettings) { AjustesView(igLogged: $igLogged, openLogin: { showLogin = true }) }
        .sheet(isPresented: $showLogin) { IGLoginView { igLogged = true; phase = .done("instagram conectado") } }
    }

    private var isWorking: Bool { if case .working = phase { return true } else { return false } }

    private func label(_ s: String, filled: Bool) -> some View {
        Text(s.uppercased())
            .font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(1.5)
            .foregroundStyle(filled ? Color.black : ink)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(filled ? accent : Color.clear)
            .overlay(Rectangle().stroke(filled ? accent : ink.opacity(0.25), lineWidth: 1))
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .idle: EmptyView()
        case .working(let m):
            HStack(spacing: 10) { ProgressView().tint(accent); Text(m).foregroundStyle(ink.opacity(0.7)) }
                .font(.system(size: 14, design: .monospaced))
        case .done(let m):
            Text(m).font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
        case .failed(let m):
            Text(m).font(.system(size: 14, design: .monospaced)).foregroundStyle(Color(red: 1, green: 0.5, blue: 0.5))
        }
    }

    private func igButton() {
        if igLogged { Task { await IGSession.logout(); igLogged = false } } else { showLogin = true }
    }

    private func paste() {
        if let s = UIPasteboard.general.string { text = s; if Ajuste.on(Ajuste.autoStart) { start() } }
    }

    private func grabClipboardIfLink() {
        guard Ajuste.on(Ajuste.clipboard), text.isEmpty, UIPasteboard.general.hasStrings,
              let s = UIPasteboard.general.string, Downloader.extractLink(s) != nil else { return }
        text = s
    }

    private func start() {
        focused = false
        guard !isWorking else { return }
        guard let link = Downloader.extractLink(text) else { phase = .failed(GuardarError.badLink.localizedDescription); return }
        Task {
            do {
                phase = .working("buscando video")
                let clip = try await Downloader.fetch(link)
                phase = .working("guardando en fotos")
                let n = try await Downloader.save(clip)
                phase = .done(n == 1 ? "guardado en fotos" : "\(n) fotos guardadas")
                text = ""
                if Ajuste.on(Ajuste.haptics) { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            } catch {
                phase = .failed(error.localizedDescription)
                if Ajuste.on(Ajuste.haptics) { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            }
        }
    }
}
