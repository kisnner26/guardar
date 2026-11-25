import SwiftUI

enum Ajuste {
    static let clipboard = "auto_clipboard"      // detectar link al abrir
    static let autoStart = "auto_start_paste"    // descargar al tocar pegar
    static let album = "guardar_en_album"        // album propio "Guardar"
    static let hd = "calidad_hd"                 // tiktok en hd
    static let haptics = "vibracion"

    static func registrar() {
        UserDefaults.standard.register(defaults: [clipboard: true, autoStart: true, album: false, hd: true, haptics: true])
    }
    static func on(_ k: String) -> Bool { UserDefaults.standard.bool(forKey: k) }
}

struct AjustesView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Ajuste.clipboard) private var clipboard = true
    @AppStorage(Ajuste.autoStart) private var autoStart = true
    @AppStorage(Ajuste.album) private var album = false
    @AppStorage(Ajuste.hd) private var hd = true
    @AppStorage(Ajuste.haptics) private var haptics = true
    @Binding var igLogged: Bool
    var openLogin: () -> Void

    private let ink = Color(red: 0.96, green: 0.94, blue: 0.89)
    private let accent = Color(red: 1.0, green: 0.36, blue: 0.2)

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("AJUSTES").font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(3).foregroundStyle(accent)
                        Spacer()
                        Button("CERRAR") { dismiss() }
                            .font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(2)
                            .foregroundStyle(ink.opacity(0.6))
                    }.padding(.top, 28)

                    section("descarga")
                    row("calidad hd en tiktok", "usa la version de mayor resolucion", $hd)
                    row("album \"Guardar\"", "ademas de la galeria, agrupa todo en un album propio", $album)

                    section("entrada")
                    row("detectar link al abrir", "si copiaste un link, aparece listo en la caja", $clipboard)
                    row("descargar al pegar", "el boton pegar tambien inicia la descarga", $autoStart)

                    section("sensaciones")
                    row("vibracion", "respuesta al terminar o fallar", $haptics)

                    section("instagram")
                    Button(action: { igLogged ? disconnect() : { dismiss(); openLogin() }() }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(igLogged ? "sesion conectada" : "sin sesion")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                                Text(igLogged ? "toca para cerrar sesion y borrar las cookies" : "necesaria solo para reels que bloquean la descarga")
                                    .font(.system(size: 12)).foregroundStyle(ink.opacity(0.5)).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Text((igLogged ? "salir" : "entrar").uppercased())
                                .font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.5)
                                .foregroundStyle(accent)
                        }.padding(.vertical, 14)
                    }

                    section("acerca de")
                    Text("Guardar \(version)\nlos videos van directo a fotos. nada se sube a ningun lado y no hay cuentas ni anuncios.\ntiktok usa el servicio publico tikwm.com; instagram se lee directo desde instagram.com.")
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.opacity(0.45)).lineSpacing(4)
                        .padding(.bottom, 40)
                }.padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func disconnect() { Task { await IGSession.logout(); igLogged = false } }

    private func section(_ t: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t.uppercased()).font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2).foregroundStyle(ink.opacity(0.4)).padding(.top, 30).padding(.bottom, 8)
            Rectangle().fill(ink.opacity(0.15)).frame(height: 1)
        }
    }

    private func row(_ title: String, _ sub: String, _ v: Binding<Bool>) -> some View {
        Toggle(isOn: v) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                Text(sub).font(.system(size: 12)).foregroundStyle(ink.opacity(0.5))
            }
        }
        .tint(accent).padding(.vertical, 12)
    }
}

struct IntroView: View {
    @State private var appear = false
    private let ink = Color(red: 0.96, green: 0.94, blue: 0.89)
    private let accent = Color(red: 1.0, green: 0.36, blue: 0.2)

    var body: some View {
        ZStack {
            Color(red: 0.05, green: 0.05, blue: 0.05).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottom) {
                    Rectangle().fill(ink).frame(width: 74, height: 8)
                    Triangle().fill(accent).frame(width: 74, height: 44)
                        .offset(y: appear ? -26 : -150).opacity(appear ? 1 : 0)
                }.frame(width: 74, height: 110, alignment: .bottom).clipped()
                Text("guardar")
                    .font(.system(size: 52, weight: .black)).foregroundStyle(ink)
                    .opacity(appear ? 1 : 0).offset(y: appear ? 0 : 14)
                Text("pega. se guarda.")
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).tracking(2)
                    .foregroundStyle(accent).opacity(appear ? 1 : 0)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 0.7)) { appear = true } }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p
    }
}
