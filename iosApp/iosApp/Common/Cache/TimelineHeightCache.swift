import Foundation
import UIKit

 class TimelineHeightCache {
    static let shared = TimelineHeightCache()
     
     private var cache: [String: CGFloat] = [:]

    private var accessTimes: [String: Date] = [:]
    
     private let queue = DispatchQueue(label: "timeline.height.cache", qos: .userInteractive)
    
     ///  2000 × 52 bytes = 104KB * 5=
    private let maxCacheSize = 5000

     private func checkCacheCapacity() {
        let currentCount = cache.count
        let usageRate = Double(currentCount) / Double(maxCacheSize)

        if usageRate > 0.9 {
            FlareLog.warning("TimelineHeightCache ⚠️ Cache usage high: \(currentCount)/\(maxCacheSize) (\(String(format: "%.1f", usageRate * 100))%)")
        }

        if currentCount >= maxCacheSize {
            FlareLog.warning("TimelineHeightCache ⚠️ Cache at maximum capacity! Consider increasing maxCacheSize.")
        }
    }
    
     private var evictCount: Int {
        maxCacheSize / 4
    }
    
    private init() {
        FlareLog.debug("TimelineHeightCache Initialized with max size: \(maxCacheSize)")
    }
    

    func getHeight(for itemId: String) -> CGFloat? {
        return queue.sync {
            // 更新访问时间
            accessTimes[itemId] = Date()
            
            let height = cache[itemId]
            if height != nil {
                FlareLog.debug("TimelineHeightCache Cache HIT for item: \(itemId), height: \(height!)")
            }
            
            return height
        }
    }
    

    func setHeight(_ height: CGFloat, for itemId: String) {
        // 验证高度值的合理性
        guard height > 0 && height < 5000 else {
            FlareLog.debug("TimelineHeightCache Invalid height \(height) for item: \(itemId)")
            return
        }
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            // 检查缓存大小限制
            if self.cache.count >= self.maxCacheSize {
                self.checkCacheCapacity() // 🟢 监控缓存容量
                self.evictLeastRecentlyUsed()
            }
            
            // 缓存高度和访问时间
            self.cache[itemId] = height
            self.accessTimes[itemId] = Date()
            
            FlareLog.debug("TimelineHeightCache Cached height \(height) for item: \(itemId), total cached: \(self.cache.count)")
        }
    }
    
    /// 清除所有缓存
    func clearCache() {
        queue.async { [weak self] in
            guard let self = self else { return }

            let clearedCount = self.cache.count

            // 🟢 添加调用栈追踪，调查缓存清空原因
            FlareLog.warning("TimelineHeightCache ⚠️ CACHE CLEAR TRIGGERED! Removing \(clearedCount) items")
            FlareLog.debug("TimelineHeightCache Clear stack trace: \(Thread.callStackSymbols.prefix(10).joined(separator: "\n"))")

            self.cache.removeAll()
            self.accessTimes.removeAll()

            FlareLog.debug("TimelineHeightCache Cleared all cache, removed \(clearedCount) items")
        }
    }
    
    /// 清除指定item的缓存
    /// - Parameter itemId: 要清除的item标识
    func clearHeight(for itemId: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let removedHeight = self.cache.removeValue(forKey: itemId)
            self.accessTimes.removeValue(forKey: itemId)
            
            if let height = removedHeight {
                FlareLog.debug("TimelineHeightCache Cleared cache for item: \(itemId), height: \(height)")
            }
        }
    }
    
    /// 处理内存压力，清理部分缓存
    func handleMemoryPressure() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let originalCount = self.cache.count
            guard originalCount > 0 else { return }
            
            // 保留最近使用的50%
            let keepCount = originalCount / 2
            let sortedByAccess = self.accessTimes.sorted { $0.value > $1.value }
            
            // 清空缓存
            self.cache.removeAll()
            self.accessTimes.removeAll()
            
            // 恢复最近访问的项目
            for i in 0..<min(keepCount, sortedByAccess.count) {
                let itemId = sortedByAccess[i].key
                self.accessTimes[itemId] = sortedByAccess[i].value
                // 注意：这里只恢复访问时间，高度需要重新计算
            }
            
            let removedCount = originalCount - self.accessTimes.count
            FlareLog.debug("TimelineHeightCache Memory pressure handled, removed \(removedCount) items, kept \(self.accessTimes.count) items")
        }
    }
    
    /// 获取缓存统计信息
    /// - Returns: (缓存数量, 最大容量, 使用率)
    func getCacheStatistics() -> (count: Int, maxSize: Int, usage: Double) {
        return queue.sync {
            let count = cache.count
            let usage = Double(count) / Double(maxCacheSize)
            return (count, maxCacheSize, usage)
        }
    }
    
     
    /// LRU淘汰策略：移除最久未访问的项目
    private func evictLeastRecentlyUsed() {
        guard cache.count >= maxCacheSize else { return }
        
        // 按访问时间排序，最久未访问的在前
        let sortedByAccess = accessTimes.sorted { $0.value < $1.value }
        let evictCount = min(self.evictCount, sortedByAccess.count)
        
        var removedItems: [String] = []
        
        // 移除最久未访问的项目
        for i in 0..<evictCount {
            let itemId = sortedByAccess[i].key
            cache.removeValue(forKey: itemId)
            accessTimes.removeValue(forKey: itemId)
            removedItems.append(itemId)
        }
        
        FlareLog.debug("TimelineHeightCache LRU evicted \(evictCount) items, remaining: \(cache.count)")

        // 🟢 检查是否意外清空了所有缓存
        if cache.count == 0 && evictCount > 0 {
            FlareLog.warning("TimelineHeightCache ⚠️ LRU eviction cleared ALL cache! This might be unexpected.")
        }
    }
}

extension TimelineHeightCache {
    
    /// 获取详细的缓存统计信息
    func getDetailedStatistics() -> CacheStatistics {
        return queue.sync {
            let now = Date()
            let recentAccessCount = accessTimes.values.filter { now.timeIntervalSince($0) < 300 }.count // 5分钟内访问
            
            return CacheStatistics(
                totalItems: cache.count,
                maxCapacity: maxCacheSize,
                usagePercentage: Double(cache.count) / Double(maxCacheSize) * 100,
                recentAccessCount: recentAccessCount,
                oldestAccessTime: accessTimes.values.min(),
                newestAccessTime: accessTimes.values.max()
            )
        }
    }
    
    /// 缓存统计信息结构
    struct CacheStatistics {
        let totalItems: Int
        let maxCapacity: Int
        let usagePercentage: Double
        let recentAccessCount: Int
        let oldestAccessTime: Date?
        let newestAccessTime: Date?
        
        var description: String {
            return """
            TimelineHeightCache Statistics:
            - Total Items: \(totalItems)/\(maxCapacity) (\(String(format: "%.1f", usagePercentage))%)
            - Recent Access (5min): \(recentAccessCount)
            - Oldest Access: \(oldestAccessTime?.description ?? "N/A")
            - Newest Access: \(newestAccessTime?.description ?? "N/A")
            """
        }
    }
}
