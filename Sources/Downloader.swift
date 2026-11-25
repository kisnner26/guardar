import Foundation
import Photos

struct Clip {
    var title: String
    var author: String
    var cover: URL?
    var video: URL?
    var images: [URL]
}

enum GuardarError: LocalizedError {
    case badLink, notFound, denied, needsLogin, network(String)
    var errorDescription: String? {
        switch self {
        case .badLink: return "eso no parece un link de tiktok, instagram o x"
        case .notFound: return "no se pudo obtener el video. puede ser privado o haberse borrado"
        case .needsLogin: return "este reel bloquea la descarga sin cuenta. inicia sesion en instagram desde la app y vuelve a intentar"
        case .denied: return "sin permiso para la galeria. activalo en ajustes > guardar > fotos"
        case .network(let m): return m
        }
    }
}

enum Downloader {
    static func extractLink(_ text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let links = detector?.matches(in: text, range: range).compactMap { $0.url } ?? []
        return links.first { u in
            let h = u.host ?? ""
            return h.contains("tiktok.com") || h.contains("instagram.com") || isX(u)
        }
    }

    static func isX(_ u: URL) -> Bool {
        let h = (u.host ?? "").lowercased()
        let hosts = ["x.com", "twitter.com", "mobile.twitter.com", "www.x.com", "www.twitter.com", "fxtwitter.com", "vxtwitter.com", "fixupx.com"]
        return hosts.contains(h) && u.path.contains("/status/")
    }

    static func fetch(_ link: URL) async throws -> Clip {
        if isX(link) { return try await fetchX(link) }
        if (link.host ?? "").contains("instagram.com") { return try await fetchInstagram(link) }
        return try await fetchTikTok(link)
    }

    // MARK: instagram
    private static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\u0026", with: "&")
         .replacingOccurrences(of: "\\", with: "")
         .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// los links "compartir" (/share/reel/xxx) redirigen al reel real: hay que seguirlos
    private static func resolveShare(_ link: URL) async -> URL {
        guard link.path.contains("/share/") else { return link }
        var req = URLRequest(url: link)
        req.timeoutInterval = 15
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        if let (_, resp) = try? await URLSession.shared.data(for: req),
           let final = resp.url, !final.path.contains("/share/"), !final.path.contains("/accounts/login") {
            return final
        }
        return link
    }

    static func fetchInstagram(_ original: URL) async throws -> Clip {
        let link = await resolveShare(original)
        let parts = link.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(where: { ["reel", "reels", "p", "tv"].contains($0) }),
              i + 1 < parts.count else { throw GuardarError.badLink }
        let code = parts[i + 1]
        let uas = [
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"
        ]
        let pages = ["https://www.instagram.com/reel/\(code)/embed/captioned/",
                     "https://www.instagram.com/p/\(code)/embed/captioned/",
                     "https://www.instagram.com/reel/\(code)/",
                     "https://www.instagram.com/reel/\(code)/embed/"]
        for (n, page) in pages.enumerated() {
            var req = URLRequest(url: URL(string: page)!)
            req.timeoutInterval = 20
            req.setValue(uas[n == 2 ? 1 : 0], forHTTPHeaderField: "User-Agent")
            req.setValue("es-ES,es;q=0.9", forHTTPHeaderField: "Accept-Language")
            guard let (data, _) = try? await URLSession.shared.data(for: req),
                  let html = String(data: data, encoding: .utf8) else { continue }
            let raw = firstMatch(#"video_url\\+":\\+"(.*?)\\+""#, in: html)
                ?? firstMatch(#"property="og:video(?::secure_url)?" content="([^"]+)""#, in: html)
                ?? firstMatch(#"<video[^>]+src="([^"]+)""#, in: html)
            if let raw, let url = URL(string: unescape(raw)) {
                let cover = firstMatch(#"property="og:image" content="([^"]+)""#, in: html)
                    .flatMap { URL(string: unescape($0)) }
                return Clip(title: "", author: "", cover: cover, video: url, images: [])
            }
        }
        // el embed no sirve para este reel: usar la sesion del usuario si existe
        guard await IGSession.isLoggedIn() else { throw GuardarError.needsLogin }
        return try await fetchInstagramWithSession(code)
    }

    private static func mediaID(from code: String) -> String? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var id = 0
        for ch in code.prefix(11) {
            guard let i = alphabet.firstIndex(of: ch) else { return nil }
            id = id &* 64 &+ i
        }
        return String(id)
    }

    private static func fetchInstagramWithSession(_ code: String) async throws -> Clip {
        guard let id = mediaID(from: code) else { throw GuardarError.badLink }
        await IGSession.syncToURLSession()
        var req = URLRequest(url: URL(string: "https://www.instagram.com/api/v1/media/\(id)/info/")!)
        req.timeoutInterval = 20
        req.setValue("936619743392459", forHTTPHeaderField: "X-IG-App-ID")
        req.setValue("https://www.instagram.com/reel/\(code)/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { await IGSession.logout(); throw GuardarError.needsLogin }
        guard status == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = (root["items"] as? [[String: Any]])?.first else { throw GuardarError.notFound }
        let versions = item["video_versions"] as? [[String: Any]] ?? []
        let best = versions.max { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }
        if let u = (best?["url"] as? String).flatMap(URL.init) {
            let cover = ((item["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]])?
                .first?["url"] as? String
            return Clip(title: "", author: "", cover: cover.flatMap(URL.init), video: u, images: [])
        }
        // carrusel o foto
        let nodes = (item["carousel_media"] as? [[String: Any]]) ?? [item]
        let imgs: [URL] = nodes.compactMap { n in
            let cands = (n["image_versions2"] as? [String: Any])?["candidates"] as? [[String: Any]]
            return (cands?.first?["url"] as? String).flatMap { URL(string: $0) }
        }
        if !imgs.isEmpty { return Clip(title: "", author: "", cover: nil, video: nil, images: imgs) }
        throw GuardarError.notFound
    }

    // MARK: x (twitter)
    static func fetchX(_ link: URL) async throws -> Clip {
        let parts = link.pathComponents.filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "status"), i + 1 < parts.count, i >= 1 else { throw GuardarError.badLink }
        let user = parts[i - 1], id = parts[i + 1].prefix { $0.isNumber }
        var req = URLRequest(url: URL(string: "https://api.fxtwitter.com/\(user)/status/\(id)")!)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tweet = root["tweet"] as? [String: Any] else { throw GuardarError.notFound }
        // el video puede venir en el tweet o en el tweet citado
        let media = (tweet["media"] as? [String: Any])
            ?? ((tweet["quote"] as? [String: Any])?["media"] as? [String: Any])
        let all = (media?["all"] as? [[String: Any]]) ?? []
        let videos = (media?["videos"] as? [[String: Any]] ?? []) + all.filter { ["video", "gif"].contains($0["type"] as? String ?? "") }
        if let v = videos.compactMap({ ($0["url"] as? String).flatMap { URL(string: $0) } }).first {
            let thumb = (videos.first?["thumbnail_url"] as? String).flatMap { URL(string: $0) }
            return Clip(title: tweet["text"] as? String ?? "", author: user, cover: thumb, video: v, images: [])
        }
        let photos = (media?["photos"] as? [[String: Any]] ?? []).compactMap { ($0["url"] as? String).flatMap { URL(string: $0) } }
        if !photos.isEmpty { return Clip(title: "", author: user, cover: nil, video: nil, images: photos) }
        throw GuardarError.notFound
    }

    // MARK: tiktok
    static func fetchTikTok(_ link: URL) async throws -> Clip {
        var comps = URLComponents(string: "https://www.tikwm.com/api/")!
        comps.queryItems = [.init(name: "url", value: link.absoluteString), .init(name: "hd", value: "1")]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 25
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["code"] as? Int) == 0,
              let d = root["data"] as? [String: Any] else { throw GuardarError.notFound }
        let images = (d["images"] as? [String] ?? []).compactMap(URL.init)
        let wantHD = Ajuste.on(Ajuste.hd)
        let hdURL = (d["hdplay"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let v = (wantHD ? hdURL : nil) ?? (d["play"] as? String) ?? hdURL
        let author = (d["author"] as? [String: Any])?["unique_id"] as? String ?? ""
        let clip = Clip(title: d["title"] as? String ?? "",
                        author: author,
                        cover: (d["cover"] as? String).flatMap(URL.init),
                        video: images.isEmpty ? v.flatMap(URL.init) : nil,
                        images: images)
        if clip.video == nil && clip.images.isEmpty { throw GuardarError.notFound }
        return clip
    }

    private static func download(_ url: URL, ext: String) async throws -> URL {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 { throw GuardarError.notFound }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    private static let albumName = "Guardar"
    private static func findAlbum() -> PHAssetCollection? {
        let o = PHFetchOptions(); o.predicate = NSPredicate(format: "title = %@", albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: o).firstObject
    }

    /// descarga y guarda directo en fotos. devuelve cuantos elementos se guardaron
    static func save(_ clip: Clip) async throws -> Int {
        let useAlbum = Ajuste.on(Ajuste.album)
        let status = await PHPhotoLibrary.requestAuthorization(for: useAlbum ? .readWrite : .addOnly)
        guard status == .authorized || status == .limited else { throw GuardarError.denied }

        var files: [(URL, Bool)] = []   // (archivo, esVideo)
        if let v = clip.video {
            files.append((try await download(v, ext: "mp4"), true))
        } else {
            for u in clip.images { files.append((try await download(u, ext: "jpg"), false)) }
        }
        defer { files.forEach { try? FileManager.default.removeItem(at: $0.0) } }

        let album = useAlbum ? findAlbum() : nil
        try await PHPhotoLibrary.shared().performChanges {
            var placeholders: [PHObjectPlaceholder] = []
            for (f, isVideo) in files {
                let r = isVideo ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: f)
                                : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: f)
                if let ph = r?.placeholderForCreatedAsset { placeholders.append(ph) }
            }
            if useAlbum {
                let req = album.flatMap { PHAssetCollectionChangeRequest(for: $0) }
                    ?? PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                req.addAssets(placeholders as NSArray)
            }
        }
        return files.count
    }
}
