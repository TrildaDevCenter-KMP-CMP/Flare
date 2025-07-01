import Foundation
import SwiftUI
import UIKit

 
class TimelineHeightPreloader {

    static let shared = TimelineHeightPreloader()


     private let sharedRouter = FlareRouter()
    private let sharedAppSettings = AppSettings()

    /// 预计算锁（用于并发控制）
    private let preloadLock = NSLock()

     private var preloadingItems: Set<String> = []


    private init() {
        FlareLog.debug("TimelineHeightPreloader Initialized with shared router: \(ObjectIdentifier(sharedRouter))")
    }
    

     func batchPreloadHeights(for items: [TimelineItem], screenWidth: CGFloat) async {
        // 🟢 正确逻辑：只计算没有缓存的item（新增的item）
        let itemsNeedingPreload = items.filter { item in
            TimelineHeightCache.shared.getHeight(for: item.id) == nil
        }

        guard !itemsNeedingPreload.isEmpty else {
            FlareLog.debug("TimelineHeightPreloader ⏱️ All items already have cached heights, skipping preload")
            return
        }

        let maxConcurrent = 5 // 🟢 统一并发数，与preloadSingleItemHeight保持一致

        // 🟢 开始计时
        let startTime = CFAbsoluteTimeGetCurrent()
        FlareLog.debug("TimelineHeightPreloader ⏱️ Starting batch preload for \(itemsNeedingPreload.count) new items (total: \(items.count))")

        // 分批处理，避免一次性创建过多Task
        let batches = stride(from: 0, to: itemsNeedingPreload.count, by: maxConcurrent).map { startIndex in
            let endIndex = min(startIndex + maxConcurrent, itemsNeedingPreload.count)
            return Array(itemsNeedingPreload[startIndex..<endIndex])
        }

        for batch in batches {
            await withTaskGroup(of: Void.self) { group in
                for item in batch {
                    group.addTask {
                        await self.preloadSingleItemHeight(item: item, screenWidth: screenWidth)
                    }
                }
            }
        }

        // 🟢 结束计时并记录耗时
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = (endTime - startTime) * 1000 // 转换为毫秒
        FlareLog.debug("TimelineHeightPreloader ⏱️ Batch preload completed for \(itemsNeedingPreload.count) new items in \(String(format: "%.2f", duration))ms")
    }

 
    /// 清除预计算状态
    func clearPreloadingState() {
        preloadLock.lock()
        defer { preloadLock.unlock() }

        preloadingItems.removeAll()

        FlareLog.debug("TimelineHeightPreloader Cleared preloading state")
    }
    
      
    /// 离屏计算item高度
    /// - Parameters:
    ///   - item: 要计算的Timeline item
    ///   - screenWidth: 屏幕宽度
    private func calculateHeightOffscreen(for item: TimelineItem, screenWidth: CGFloat) {
        // 确保在主线程创建UIHostingController
        DispatchQueue.main.async { [weak self] in
            self?.performOffscreenCalculation(for: item, screenWidth: screenWidth)
        }
    }
    
    /// 在主线程执行离屏计算
    /// - Parameters:
    ///   - item: 要计算的Timeline item
    ///   - screenWidth: 屏幕宽度
    private func performOffscreenCalculation(for item: TimelineItem, screenWidth: CGFloat) {
        let startTime = CFAbsoluteTimeGetCurrent()

        // 🟢 创建带有完整环境对象的离屏渲染View（使用共享实例）
        let contentView = TimelineStatusViewV2(
            item: item,
            index: 0,
            presenter: nil,
            scrollPositionID: .constant(nil),
            onError: { _ in }
        )
        .frame(width: screenWidth - 32)
        .environment(FlareTheme.shared)
        .environmentObject(sharedRouter)
        .environment(\.appSettings, sharedAppSettings)  

        // 创建UIHostingController
        let hostingController = UIHostingController(rootView: contentView)

        // 计算高度
        let targetSize = CGSize(
            width: screenWidth - 32,
            height: UIView.layoutFittingExpandedSize.height
        )

        let calculatedSize = hostingController.sizeThatFits(in: targetSize)

        // 🟢 改进的高度验证和容错机制
        let finalHeight: CGFloat
        if calculatedSize.height <= 0 {
            // 高度为0或负数，使用默认最小高度
            finalHeight = 50.0
            FlareLog.warning("TimelineHeightPreloader Zero/negative height \(calculatedSize.height) for item: \(item.id), using default 50.0")
        } else if calculatedSize.height >= 10000.0 {
            // 检测到10000.0（可能是敏感内容的EmptyView），使用最小高度
            finalHeight = 1.0
            FlareLog.warning("TimelineHeightPreloader Detected EmptyView height \(calculatedSize.height) for item: \(item.id), likely sensitive content, using minimal height 1.0")
        } else if calculatedSize.height > 3000 {
            // 高度过大，使用最大限制
            finalHeight = 3000.0
            FlareLog.warning("TimelineHeightPreloader Excessive height \(calculatedSize.height) for item: \(item.id), clamped to 3000.0")
        } else {
            // 正常高度
            finalHeight = calculatedSize.height
        }

        // 缓存结果
        TimelineHeightCache.shared.setHeight(finalHeight, for: item.id)

        let calculationTime = CFAbsoluteTimeGetCurrent() - startTime
        FlareLog.debug("TimelineHeightPreloader Preloaded height \(finalHeight) (original: \(calculatedSize.height)) for item: \(item.id) in \(String(format: "%.2f", calculationTime * 1000))ms")

        // 清理UIHostingController
        hostingController.view.removeFromSuperview()
    }

    /// 预计算单个item的高度（用于批量预计算）
    /// - Parameters:
    ///   - item: 要预计算的Timeline item
    ///   - screenWidth: 屏幕宽度
    private func preloadSingleItemHeight(item: TimelineItem, screenWidth: CGFloat) async {
        // 🟢 移除重复的缓存检查，因为batchPreloadHeights已经过滤过了

        // 使用同步方式检查并发限制
        let shouldProceed = await MainActor.run {
            preloadLock.lock()
            defer { preloadLock.unlock() }

            let currentPreloading = preloadingItems.count
            let maxConcurrent = 5 // 🟢 使用固定的并发限制
            if currentPreloading >= maxConcurrent {
                return false // 达到并发限制，跳过
            }

            // 添加到正在预计算的集合
            preloadingItems.insert(item.id)
            return true
        }

        guard shouldProceed else { return }

        defer {
            // 清理：从正在预计算的集合中移除
            Task { @MainActor in
                preloadLock.lock()
                preloadingItems.remove(item.id)
                preloadLock.unlock()
            }
        }

        // 执行高度计算（使用现有的同步方法）
        calculateHeightOffscreen(for: item, screenWidth: screenWidth)
    }
}

 
