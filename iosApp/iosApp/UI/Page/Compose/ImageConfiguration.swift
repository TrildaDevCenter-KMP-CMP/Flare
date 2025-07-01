import Foundation
import Kingfisher
import UIKit

public final class FlareImageConfiguration {
    public static let shared = FlareImageConfiguration()

    private init() {}

    public func configure() {
        configureImageCache()
        configureImageDownloader()
        setupMemoryPressureHandling()

        FlareLog.info("FlareImageConfiguration Image configuration applied successfully")
    }

    private func configureImageCache() {
        let cache = ImageCache.default

        let memoryLimit = calculateOptimalMemoryLimit()
        cache.memoryStorage.config.totalCostLimit = Int(memoryLimit)

        cache.memoryStorage.config.countLimit = UIDevice.current.userInterfaceIdiom == .pad ? 200 : 100

        cache.diskStorage.config.sizeLimit = 100 * 1024 * 1024

        cache.diskStorage.config.expiration = .days(7)

        cache.memoryStorage.config.expiration = .seconds(300)

        FlareLog.info("ImageCache Memory limit: \(memoryLimit / 1024 / 1024)MB, Disk limit: 100MB")
    }

    private func calculateOptimalMemoryLimit() -> UInt {
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let deviceType = UIDevice.current.userInterfaceIdiom

        // 🟢 采用更接近Kingfisher官方推荐的策略
        // Use strategy closer to Kingfisher official recommendations
        let percentage = switch deviceType {
        case .pad: 0.20 // iPad: 20% (接近官方25%)
        case .phone: 0.15 // iPhone: 15% (适中策略)
        default: 0.12 // 其他设备: 12%
        }

        let calculatedLimit = UInt(Double(totalMemory) * percentage)

        // 🟢 提高上限，接近官方推荐
        // Increase upper limit, closer to official recommendations
        let minLimit: UInt = 50 * 1024 * 1024 // 最小50MB
        let maxLimit: UInt = 300 * 1024 * 1024 // 🟢 提高到300MB (官方推荐)

        return max(minLimit, min(maxLimit, calculatedLimit))
    }

    private func configureImageDownloader() {
        let downloader = ImageDownloader.default

         downloader.downloadTimeout = 15.0

         downloader.sessionConfiguration.httpMaximumConnectionsPerHost = 6

        FlareLog.debug("ImageDownloader Timeout: 15s, Max connections: 6")
    }

    private func setupMemoryPressureHandling() {
        // 🟢 监听内存警告
        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryPressure()
        }

        // 🟢 监听应用进入后台
        // Listen for app entering background
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleBackgroundCleanup()
        }
    }

    private func handleMemoryPressure() {
        FlareLog.warning("FlareImageConfiguration Memory pressure detected, performing aggressive cleanup")

        // 🟢 更激进的清理策略
        // More aggressive cleanup strategy
        ImageCache.default.clearMemoryCache()
        ImageCache.default.cleanExpiredDiskCache()

        // 🟢 临时降低内存限制
        // Temporarily reduce memory limit
        let currentLimit = ImageCache.default.memoryStorage.config.totalCostLimit
        ImageCache.default.memoryStorage.config.totalCostLimit = currentLimit / 2

        FlareLog.info("FlareImageConfiguration Temporarily reduced memory limit to \(currentLimit / 2 / 1024 / 1024)MB")

        // 🟢 5分钟后恢复正常限制
        // Restore normal limit after 5 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            ImageCache.default.memoryStorage.config.totalCostLimit = currentLimit
            FlareLog.info("FlareImageConfiguration Restored memory limit to \(currentLimit / 1024 / 1024)MB")
        }
    }

    private func handleBackgroundCleanup() {
        FlareLog.info("FlareImageConfiguration App entered background, performing cleanup")

        ImageCache.default.cleanExpiredDiskCache()
    }
}

public enum FlareImageOptions {
    public static func avatar(size: CGSize) -> KingfisherOptionsInfo {
        [
            .processor(DownsamplingImageProcessor(size: size)),
            .scaleFactor(UIScreen.main.scale),
            .memoryCacheExpiration(.seconds(300)),
            .diskCacheExpiration(.days(7)),
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
        ]
    }

    public static func banner(size: CGSize) -> KingfisherOptionsInfo {
        [
            .processor(DownsamplingImageProcessor(size: size)),
            .scaleFactor(UIScreen.main.scale),
            .memoryCacheExpiration(.seconds(180)),
            .diskCacheExpiration(.days(3)),
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
        ]
    }

    public static func mediaPreview(size: CGSize) -> KingfisherOptionsInfo {
        [
            .processor(DownsamplingImageProcessor(size: size)),
            .scaleFactor(UIScreen.main.scale),
            .memoryCacheExpiration(.seconds(300)), // 🟢 从600秒减少到300秒，减少内存占用
            .diskCacheExpiration(.days(7)), // 🟢 从14天减少到7天
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
        ]
    }

    public static func fullScreen(size: CGSize) -> KingfisherOptionsInfo {
        [
            .processor(DownsamplingImageProcessor(size: size)),
            .scaleFactor(UIScreen.main.scale),
            .memoryCacheExpiration(.seconds(180)), // 🟢 从120秒增加到180秒（平衡性能和内存）
            .diskCacheExpiration(.days(14)), // 🟢 从30天减少到14天
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
        ]
    }

    public static func serviceIcon(size: CGSize) -> KingfisherOptionsInfo {
        [
            .processor(DownsamplingImageProcessor(size: size)),
            .scaleFactor(UIScreen.main.scale),
            .memoryCacheExpiration(.seconds(3600)), // 🟢 从never改为1小时，避免内存泄漏
            .diskCacheExpiration(.days(30)),
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
        ]
    }
}

public extension KFImage {
    func flareAvatar(size: CGSize) -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: size))
            .scaleFactor(UIScreen.main.scale)
            .memoryCacheExpiration(.seconds(300))
            .diskCacheExpiration(.days(7))
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
    }

    func flareBanner(size: CGSize) -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: size))
            .scaleFactor(UIScreen.main.scale)
            .memoryCacheExpiration(.seconds(180))
            .diskCacheExpiration(.days(3))
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
    }

    func flareMediaPreview(size: CGSize) -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: size))
            .scaleFactor(UIScreen.main.scale)
            .memoryCacheExpiration(.seconds(300)) // 🟢 从600秒减少到300秒
            .diskCacheExpiration(.days(7)) // 🟢 从14天减少到7天
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
    }

    func flareFullScreen(size: CGSize) -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: size))
            .scaleFactor(UIScreen.main.scale)
            .memoryCacheExpiration(.seconds(180)) // 🟢 从120秒增加到180秒
            .diskCacheExpiration(.days(14)) // 🟢 从30天减少到14天
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
    }

    func flareServiceIcon(size: CGSize) -> KFImage {
        setProcessor(DownsamplingImageProcessor(size: size))
            .scaleFactor(UIScreen.main.scale)
            .memoryCacheExpiration(.seconds(3600)) // 🟢 从never改为1小时
            .diskCacheExpiration(.days(30))
            // 🟢 移除.cacheOriginalImage，默认不缓存原图
    }
}
