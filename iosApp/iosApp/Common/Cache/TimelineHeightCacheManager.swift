import Foundation
import UIKit

class TimelineHeightCacheManager {
    

    static let shared = TimelineHeightCacheManager()
    
     private var isInitialized = false
     private var notificationObservers: [NSObjectProtocol] = []
 

    private init() {
        setupNotificationObservers()
        FlareLog.debug("TimelineHeightCacheManager Initialized")
    }
    
    deinit {
        removeNotificationObservers()
        FlareLog.debug("TimelineHeightCacheManager Deinitialized")
    }
    
     func start() {
        guard !isInitialized else {
            FlareLog.debug("TimelineHeightCacheManager Already initialized")
            return
        }
        
        isInitialized = true
        FlareLog.debug("TimelineHeightCacheManager Started")
    }
     func stop() {
        guard isInitialized else {
            FlareLog.debug("TimelineHeightCacheManager Not initialized")
            return
        }
        
        isInitialized = false
        removeNotificationObservers()
        FlareLog.debug("TimelineHeightCacheManager Stopped")
    }
    
     func invalidateCache(for itemId: String) {
        TimelineHeightCache.shared.clearHeight(for: itemId)
        FlareLog.debug("TimelineHeightCacheManager Manually invalidated cache for item: \(itemId)")
    }
    
     func invalidateAllCache() {
        TimelineHeightCache.shared.clearCache()
        FlareLog.debug("TimelineHeightCacheManager Manually invalidated all cache")
    }
    

    private func setupNotificationObservers() {
        // 设备方向变化通知
        let orientationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleOrientationChange()
        }
        notificationObservers.append(orientationObserver)
        
        // 字体大小变化通知
        let fontSizeObserver = NotificationCenter.default.addObserver(
            forName: UIContentSizeCategory.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleFontSizeChange()
        }
        notificationObservers.append(fontSizeObserver)
        
        // 内存警告通知
        let memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        notificationObservers.append(memoryWarningObserver)
        
        // 应用进入后台通知
        let backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
        notificationObservers.append(backgroundObserver)
        
        // 应用进入前台通知
        let foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppWillEnterForeground()
        }
        notificationObservers.append(foregroundObserver)
        
        FlareLog.debug("TimelineHeightCacheManager Notification observers setup completed")
    }
    
     private func removeNotificationObservers() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
        FlareLog.debug("TimelineHeightCacheManager Notification observers removed")
    }
    

    /// 处理设备方向变化
    private func handleOrientationChange() {
        guard isInitialized else { return }
 
        FlareLog.debug("TimelineHeightCacheManager Orientation change detected - keeping all cache (no performance impact)")

        // 🟢 只记录方向变化，不做任何缓存操作
        let currentOrientation = UIDevice.current.orientation
        FlareLog.debug("TimelineHeightCacheManager Current orientation: \(currentOrientation.rawValue)")
    }
    
     private func handleFontSizeChange() {
        guard isInitialized else { return }
        
        // 字体大小变化会影响文本高度，需要清除所有缓存
        TimelineHeightCache.shared.clearCache()
        FlareLog.debug("TimelineHeightCacheManager Cleared cache due to font size change")
    }
    
     private func handleMemoryWarning() {
        guard isInitialized else { return }
        
        // 内存警告时，清理部分缓存以释放内存
        TimelineHeightCache.shared.handleMemoryPressure()
        FlareLog.debug("TimelineHeightCacheManager Handled memory warning")
    }
    
    /// 处理应用进入后台
    private func handleAppDidEnterBackground() {
        guard isInitialized else { return }
        
        // 应用进入后台时，可以选择性地清理缓存
        // 这里暂时不清理，保持缓存以便用户返回时快速显示
        FlareLog.debug("TimelineHeightCacheManager App entered background")
        
        // 可选：如果需要在后台清理缓存，取消注释下面的代码
        // TimelineHeightCache.shared.handleMemoryPressure()
    }
    
    /// 处理应用即将进入前台
    private func handleAppWillEnterForeground() {
        guard isInitialized else { return }
        
        FlareLog.debug("TimelineHeightCacheManager App will enter foreground")
        
        // 可选：检查缓存状态或进行清理
        let stats = TimelineHeightCache.shared.getCacheStatistics()
        FlareLog.debug("TimelineHeightCacheManager Cache status: \(stats.count)/\(stats.maxSize) items")
    }
}


extension TimelineHeightCacheManager {
    
    /// 获取缓存管理器状态
    var status: CacheManagerStatus {
        let cacheStats = TimelineHeightCache.shared.getCacheStatistics()
        return CacheManagerStatus(
            isInitialized: isInitialized,
            observerCount: notificationObservers.count,
            cacheCount: cacheStats.count,
            cacheUsage: cacheStats.usage
        )
    }
    
    /// 缓存管理器状态结构
    struct CacheManagerStatus {
        let isInitialized: Bool
        let observerCount: Int
        let cacheCount: Int
        let cacheUsage: Double
        
        var description: String {
            return """
            TimelineHeightCacheManager Status:
            - Initialized: \(isInitialized)
            - Observers: \(observerCount)
            - Cache Items: \(cacheCount)
            - Cache Usage: \(String(format: "%.1f", cacheUsage * 100))%
            """
        }
    }
} 