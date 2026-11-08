// Renders SVG files to PNG with WebKit (no third-party tools).
//
//   swift scripts/render-svg.swift <file.svg> <pixels> <out.png> [<file.svg> <pixels> <out.png> ...]
//
// Each SVG is drawn by WKWebView at 2x or more of the target size (at least 512 pt, so blur
// filters and anti-aliasing are computed at high resolution), snapshotted, then halved step by
// step with Core Graphics down to exactly <pixels> x <pixels>. Transparency is kept.
import AppKit
import WebKit

struct Job {
    let svg: URL
    let pixels: Int
    let out: URL
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty, args.count % 3 == 0 else {
    FileHandle.standardError.write("usage: render-svg.swift <file.svg> <pixels> <out.png> ...\n".data(using: .utf8)!)
    exit(2)
}
let jobs: [Job] = stride(from: 0, to: args.count, by: 3).map { i in
    guard let px = Int(args[i + 1]), px > 0 else {
        FileHandle.standardError.write("bad size: \(args[i + 1])\n".data(using: .utf8)!)
        exit(2)
    }
    return Job(svg: URL(fileURLWithPath: args[i]), pixels: px, out: URL(fileURLWithPath: args[i + 2]))
}

/// Points to render at: twice the target size (supersampling), doubled until it is at least 512.
func renderPoints(for pixels: Int) -> Int {
    var p = pixels * 2
    while p < 512 { p *= 2 }
    return p
}

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func resized(_ image: CGImage, to px: Int) -> CGImage {
    let ctx = bitmap(px, px)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

/// Halves the image while that stays at or above the target, then scales to it exactly.
func downsample(_ image: CGImage, to px: Int) -> CGImage {
    var img = image
    while img.width / 2 >= px { img = resized(img, to: img.width / 2) }
    return img.width == px ? img : resized(img, to: px)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-svg", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
    }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

@MainActor
final class Renderer: NSObject, WKNavigationDelegate {
    private var queue: [Job]
    private let window: NSWindow
    private let webView: WKWebView
    private var current: Job?
    private var points = 0

    init(jobs: [Job]) {
        queue = jobs
        window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 64, height: 64),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        super.init()
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        window.contentView = webView
        window.orderFrontRegardless()
    }

    func next() {
        guard !queue.isEmpty else { exit(0) }
        let job = queue.removeFirst()
        current = job
        points = renderPoints(for: job.pixels)
        window.setContentSize(NSSize(width: points, height: points))
        webView.frame = NSRect(x: 0, y: 0, width: points, height: points)
        guard let svg = try? Data(contentsOf: job.svg) else { fail("cannot read \(job.svg.path)") }
        let html = """
        <!DOCTYPE html><html><head><style>
        html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        img{display:block;width:\(points)px;height:\(points)px}
        </style></head><body><img src="data:image/svg+xml;base64,\(svg.base64EncodedString())"></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Give WebKit a moment to decode the image and run its filters.
            try? await Task.sleep(for: .milliseconds(400))
            self.snapshot()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.fail("load failed: \(error)") }
    }

    private func snapshot() {
        guard let job = current else { return }
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: points, height: points)
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.fail("snapshot failed: \(String(describing: error))")
            }
            do {
                try writePNG(downsample(cg, to: job.pixels), to: job.out)
                print("\(job.out.lastPathComponent): \(job.pixels)x\(job.pixels) from \(job.svg.lastPathComponent) (snapshot \(cg.width) px)")
            } catch {
                self.fail("\(error)")
            }
            self.next()
        }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write("render-svg: \(message)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = MainActor.assumeIsolated { Renderer(jobs: jobs) }
MainActor.assumeIsolated { renderer.next() }
app.run()
