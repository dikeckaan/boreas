// Renders SVG files to PNG with WebKit (no third-party tools).
//
//   swift scripts/render-svg.swift <file.svg> <size> <out.png> [<file.svg> <size> <out.png> ...]
//
// <size> is either N (a square, N x N pixels) or WxH (for example 1320x840).
// Each SVG is drawn by WKWebView at 2x or more of the target size (at least 512 pt on the longer
// side, so blur filters and anti-aliasing are computed at high resolution), snapshotted, then
// halved step by step with Core Graphics down to exactly the target size. Transparency is kept.
import AppKit
import WebKit

struct Job {
    let svg: URL
    let width: Int
    let height: Int
    let out: URL
}

let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty, args.count % 3 == 0 else {
    FileHandle.standardError.write("usage: render-svg.swift <file.svg> <pixels> <out.png> ...\n".data(using: .utf8)!)
    exit(2)
}
let jobs: [Job] = stride(from: 0, to: args.count, by: 3).map { i in
    let parts = args[i + 1].split(separator: "x").compactMap { Int($0) }
    guard (parts.count == 1 || parts.count == 2), parts.allSatisfy({ $0 > 0 }) else {
        FileHandle.standardError.write("bad size: \(args[i + 1])\n".data(using: .utf8)!)
        exit(2)
    }
    return Job(svg: URL(fileURLWithPath: args[i]), width: parts[0], height: parts.count == 2 ? parts[1] : parts[0],
               out: URL(fileURLWithPath: args[i + 2]))
}

/// Render scale: twice the target size (supersampling), doubled until the longer side is at least 512 pt.
func renderScale(for job: Job) -> Int {
    var k = 2
    while max(job.width, job.height) * k < 512 { k *= 2 }
    return k
}

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func resized(_ image: CGImage, width: Int, height: Int) -> CGImage {
    let ctx = bitmap(width, height)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

/// Halves the image while that stays at or above the target, then scales to it exactly.
func downsample(_ image: CGImage, width: Int, height: Int) -> CGImage {
    var img = image
    while img.width / 2 >= width && img.height / 2 >= height {
        img = resized(img, width: img.width / 2, height: img.height / 2)
    }
    return (img.width == width && img.height == height) ? img : resized(img, width: width, height: height)
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
    private var pointsW = 0
    private var pointsH = 0

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
        let k = renderScale(for: job)
        pointsW = job.width * k
        pointsH = job.height * k
        window.setContentSize(NSSize(width: pointsW, height: pointsH))
        webView.frame = NSRect(x: 0, y: 0, width: pointsW, height: pointsH)
        guard let svg = try? Data(contentsOf: job.svg) else { fail("cannot read \(job.svg.path)") }
        let html = """
        <!DOCTYPE html><html><head><style>
        html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        img{display:block;width:\(pointsW)px;height:\(pointsH)px}
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
        config.rect = NSRect(x: 0, y: 0, width: pointsW, height: pointsH)
        config.afterScreenUpdates = true
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                self.fail("snapshot failed: \(String(describing: error))")
            }
            do {
                try writePNG(downsample(cg, width: job.width, height: job.height), to: job.out)
                print("\(job.out.lastPathComponent): \(job.width)x\(job.height) from \(job.svg.lastPathComponent) (snapshot \(cg.width) px)")
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
