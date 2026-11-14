import ImageIO
import UIKit
import UniformTypeIdentifiers

/// GIF previews and files for the emoji board's GIF tab.
///
/// Previews are small GIFs, decoded once (shrunk to the cell, frames
/// capped) and kept in a small in-memory cache that a memory warning empties:
/// a keyboard lives on a fraction of an app's memory. The file that is sent
/// is downloaded on tap and never kept.
@MainActor
final class GifLoader {
    static let shared = GifLoader()

    private let cache = NSCache<NSString, UIImage>()
    private var waiting: [String: [(UIImage?) -> Void]] = [:]

    private init() {
        cache.totalCostLimit = 14 * 1024 * 1024
        cache.countLimit = 72
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cache.removeAllObjects() }
        }
    }

    /// A preview, animated, shrunk to about `pixels` on its longer side.
    /// Completion on the main queue, once.
    func preview(_ urlString: String, pixels: CGFloat, completion: @escaping (UIImage?) -> Void) {
        if let hit = cache.object(forKey: urlString as NSString) { completion(hit); return }
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else {
            completion(nil); return
        }
        if waiting[urlString] != nil { waiting[urlString]?.append(completion); return }
        waiting[urlString] = [completion]
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let image = ok ? data.flatMap { Self.animated($0, maxPixel: pixels) } : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let image {
                        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
                            * max(1, image.images?.count ?? 1)
                        self.cache.setObject(image, forKey: urlString as NSString, cost: cost)
                    }
                    for block in self.waiting.removeValue(forKey: urlString) ?? [] { block(image) }
                }
            }
        }.resume()
    }

    /// The GIF to send, downloaded now. Completion on the main queue.
    func full(_ urlString: String, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else {
            completion(nil); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async { completion(ok ? data : nil) }
        }.resume()
    }

    /// Puts the GIF on the pasteboard as the one thing there, as a GIF
    /// (`com.compuserve.gif`): a keyboard can type text but never an image,
    /// so the person pastes it. Only the image type is offered, so no app
    /// pastes a link instead of the picture.
    static func copy(_ data: Data) -> Bool {
        guard data.count > 8, data.prefix(3) == Data("GIF".utf8) else { return false }
        let type = UTType.gif.identifier   // "com.compuserve.gif"
        UIPasteboard.general.setItems([[type: data]], options: [:])
        return UIPasteboard.general.types.contains(type)
    }

    /// Frames of a GIF (or WebP) as one animated image, each frame shrunk by
    /// ImageIO as it is read, at most 48 of them.
    nonisolated static func animated(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        let step = max(1, count / 48)
        var frames: [UIImage] = []
        var duration: Double = 0
        for i in stride(from: 0, to: count, by: step) {
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, opts as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cg))
            duration += frameDelay(source, i) * Double(step)
        }
        guard let first = frames.first else { return nil }
        if frames.count == 1 { return first }
        return UIImage.animatedImage(with: frames, duration: max(duration, 0.1 * Double(frames.count)))
    }

    nonisolated private static func frameDelay(_ source: CGImageSource, _ i: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any] else { return 0.1 }
        let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let webp = props[kCGImagePropertyWebPDictionary] as? [CFString: Any]
        let dict = gif ?? webp ?? [:]
        let delay = (dict[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (dict[kCGImagePropertyGIFDelayTime] as? Double)
            ?? (dict[kCGImagePropertyWebPUnclampedDelayTime] as? Double)
            ?? (dict[kCGImagePropertyWebPDelayTime] as? Double) ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

/// One GIF in the grid: the preview filling a softly rounded tile.
final class GifCell: UICollectionViewCell {
    let imageView = UIImageView()
    /// The URL this cell is waiting on, so a reused cell ignores a late answer.
    var loading: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.backgroundColor = Glass.textPrimary.withAlphaComponent(0.06)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        loading = nil
        contentView.alpha = 1
    }
}
