
import Awesome
import Generated
import JXPhotoBrowser
import Kingfisher
import MarkdownUI
import os.log
import shared
import SwiftDate
import SwiftUI
import UIKit

// MARK: - Swift原生类型定义
//enum SwiftAccountType {
//    case specific(accountKey: String)
//    case active
//    case guest
//}
//
//struct SwiftMicroBlogKey {
//    let id: String
//    let host: String
//
//    init(id: String, host: String) {
//        self.id = id
//        self.host = host
//    }
//}

struct TimelineStatusViewV2: View {
    let item: TimelineItem
    let index: Int
    let presenter: TimelinePresenter?
    @Binding var scrollPositionID: String?
    let onError: (FlareError) -> Void

    // 添加TimelineStatusView需要的状态和环境变量
    let isDetail: Bool = false
    let enableTranslation: Bool = true
    @State private var showMedia: Bool = false
    @State private var showShareMenu: Bool = false

    // 🟢 新增：高度缓存相关状态
    @State private var isHeightCached: Bool = false
    @State private var measuredHeight: CGFloat?

    // 🟢 Task管理：防止Task累积导致的性能问题
    @State private var preloadTask: Task<Void, Never>?

    @Environment(\.openURL) private var openURL
    @Environment(\.appSettings) private var appSettings
    @EnvironmentObject private var router: FlareRouter
    @Environment(FlareTheme.self) private var theme

    // 媒体点击回调 - 使用Swift Media类型
    private let onMediaClick: (Int, Media) -> Void = { _, _ in }

    // 创建临时的StatusViewModel来兼容现有组件
    private var viewModel: StatusViewModel? {
        // 暂时返回nil，后续需要从TimelineItem转换为StatusViewModel
        // 或者直接修改组件使用TimelineItem
        return nil
    }

    var body: some View {
        // 🔥 新增：Timeline级别敏感内容隐藏检查
        // if shouldHideInTimeline {
        //     // 🟢 修复：为敏感内容提供固定高度，避免EmptyView导致的10000.0高度问题
        //     Rectangle()
        //         .fill(Color.clear)
        //         .frame(height: 1) // 最小高度，避免布局问题
        //         .onAppear {
        //             // 缓存敏感内容的最小高度
        //             cacheHeight(1)
        //             FlareLog.debug("TimelineStatusViewV2 Sensitive content hidden, cached minimal height for item: \(item.id)")
        //         }
        // } else {
            optimizedTimelineContent
        // }
    }

    // MARK: - 敏感内容隐藏逻辑

    /// Timeline级别敏感内容隐藏判断 - 对应V1版本StatusItemView.shouldHideInTimeline
    private var shouldHideInTimeline: Bool {
        let sensitiveSettings = appSettings.appearanceSettings.sensitiveContentSettings

        // 第一步：检查是否开启timeline隐藏功能
        guard sensitiveSettings.hideInTimeline else {
            FlareLog.debug("TimelineStatusViewV2 SensitiveContent Timeline隐藏未开启 - item.id: \(item.id)")
            return false
        }

        // 第二步：检查内容是否为敏感内容
        guard item.sensitive else {
            FlareLog.debug("TimelineStatusViewV2 SensitiveContent 内容非敏感 - item.id: \(item.id)")
            return false
        }

        // 第三步：根据时间范围设置决定是否隐藏
        if let timeRange = sensitiveSettings.timeRange {
            // 有时间范围：只在时间范围内隐藏
            let shouldHide = timeRange.isCurrentTimeInRange()
            FlareLog.debug("TimelineStatusViewV2 SensitiveContent 时间范围检查 - item.id: \(item.id), shouldHide: \(shouldHide)")
            return shouldHide
        } else {
            // 没有时间范围：总是隐藏敏感内容
            FlareLog.debug("TimelineStatusViewV2 SensitiveContent 总是隐藏敏感内容 - item.id: \(item.id)")
            return true
        }
    }

    // MARK: - 优化的Timeline内容视图（带高度缓存）

    /// 优化后的Timeline内容，集成高度缓存功能
    private var optimizedTimelineContent: some View {
        // Group {
            // if let cachedHeight = getCachedHeight() {
            //     // 🟢 使用缓存高度，避免重复布局计算
            //     timelineContent
            //         .frame(height: cachedHeight)
            //         .clipped()
            //         .onAppear {
            //             isHeightCached = true
            //             FlareLog.debug("TimelineStatusViewV2 Using cached height \(cachedHeight) for item: \(item.id)")
            //         }
            // } else {
                // 🟢 首次渲染，测量并缓存高度
                timelineContent
                    .measureHeight(identifier: "TimelineItem-\(item.id)") { height in
                        cacheHeight(height)
                        measuredHeight = height
                        isHeightCached = true
                    }
                    .onAppear {
                        FlareLog.debug("TimelineStatusViewV2 Measuring height for item: \(item.id)")
                    }
            // }
        // }
    }

    /// 原始的Timeline内容视图（保持不变）
    private var timelineContent: some View {
        // 添加详细日志
        let _ = FlareLog.debug("TimelineStatusViewV2 渲染Timeline项目")
        let _ = FlareLog.debug("TimelineStatusViewV2 item.id: \(item.id)")
        let _ = FlareLog.debug("TimelineStatusViewV2 item.hasImages: \(item.hasImages)")
        let _ = FlareLog.debug("TimelineStatusViewV2 item.images.count: \(item.images.count)")
        let _ = FlareLog.debug("TimelineStatusViewV2 item.images: \(item.images)")

        // 🟢 合并StatusContentViewV2的VStack，减少2层嵌套
        return VStack(alignment: .leading) {
            Spacer().frame(height: 2)

            // 🔥 新增：转发头部显示 - 条件显示topMessage
            if let topMessage = item.topMessage {
                StatusRetweetHeaderComponentV2(topMessage: topMessage)
                    .environmentObject(router)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            // 使用V2版本的StatusHeaderView - 直接使用TimelineItem
            StatusHeaderViewV2(
                item: item,
                isDetailView: isDetail
            )

            // 🟢 直接嵌入StatusContentViewV2的内容，避免重复VStack
            // Reply content
            if item.hasAboveTextContent, let aboveTextContent = item.aboveTextContent {
                StatusReplyViewV2(aboveTextContent: aboveTextContent)
            }

            // Content warning
            if item.hasContentWarning, let cwText = item.contentWarning {
                StatusContentWarningViewV2(contentWarning: cwText, theme: theme, openURL: openURL)
            }

            Spacer().frame(height: 10)

            // Main content
            StatusMainContentViewV2(
                item: item,
                enableTranslation: enableTranslation,
                appSettings: appSettings,
                theme: theme,
                openURL: openURL
            )

            // Media
            if item.hasImages {
                StatusMediaViewV2(
                    item: item,
                    appSettings: appSettings,
                    onMediaClick: { index, media in
                        // TODO: 需要适配Swift Media类型的回调
                        // onMediaClick(index, media)
                    }
                )
            }

            // Card (Podcast or Link Preview)
            if item.hasCard, let card = item.card {
                StatusCardViewV2(
                    card: card,
                    item: item,
                    appSettings: appSettings,
                    onPodcastCardTap: { card in
                        handlePodcastCardTap(card: card)
                    }
                )
            }

            // Quote
            if item.hasQuote {
                StatusQuoteViewV2(quotes: item.quote, onMediaClick: { index, media in
                    // TODO: 需要适配Swift Media类型的回调
                    // onMediaClick(index, media)
                })
            }

            // misskey 的+ 的emojis
            if item.hasBottomContent, let bottomContent = item.bottomContent {
                StatusBottomContentViewV2(bottomContent: bottomContent)
            }

            // Detail date
            if isDetail {
                StatusDetailDateViewV2(createdAt: item.timestamp)
            }

            // 使用V2版本的StatusActionsView
//            if let viewModel = viewModel {
//                StatusActionsViewV2(
//                    viewModel: viewModel,
//                    appSettings: appSettings,
//                    openURL: openURL,
//                    parentView: self
//                )
//            } else {
                // 暂时使用现有的V2 Actions (当viewModel为nil时)
                TimelineActionsViewV2(
                    item: item,
                    onAction: { actionType, updatedItem in
                        handleTimelineAction(actionType, item: updatedItem, at: index)
                    }
                )
//            }

            // Spacer().frame(height: 3)
        }
         .padding(.horizontal, 16)
        .frame(alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            handleStatusTap()
        }
        .onAppear {
            // 保留原有的onAppear逻辑
            // 设置滚动位置ID
            if index == 0 {
                scrollPositionID = item.id
            }

            // 🟢 智能高度预计算逻辑 - 使用管理的Task防止累积
            preloadTask = Task {
                // 触发高度预计算：每5个item或接近边界时
                if index > 0 && (index % 5 == 0 || shouldTriggerPreload(at: index)) {
                    await triggerHeightPreload(at: index)
                }
            }
        }
        .onDisappear {
            // 🟢 清理Task，防止内存泄漏和性能问题
            preloadTask?.cancel()
            preloadTask = nil

            // 可选：在View消失时进行清理
            if !isHeightCached {
                FlareLog.debug("TimelineStatusViewV2 View disappeared before height cached: \(item.id)")
            }
        }
    }
    
    // MARK: - 从TimelineStatusView复制的方法

    private func handleStatusTap() {
        // 🔥 实现推文点击跳转到详情页面
        let accountType = UserManager.shared.getCurrentAccountType() ?? AccountTypeGuest()

        // 构造MicroBlogKey - 需要从item.id和platformType构造
        let statusKey = createMicroBlogKey(from: item)

        FlareLog.debug("TimelineStatusView Navigate to status detail: \(item.id)")
        router.navigate(to: .statusDetail(
            accountType: accountType,
            statusKey: statusKey
        ))
    }

    private func handlePodcastCardTap(card: Card) {
        // 🔥 实现播客卡片点击处理
        if let route = AppDeepLinkHelper().parse(url: card.url) as? AppleRoute.Podcast {
            FlareLog.debug("TimelineStatusViewV2 Podcast Card Tapped, navigating to: podcastSheet(accountType: \(route.accountType), podcastId: \(route.id))")
            router.navigate(to: .podcastSheet(accountType: route.accountType, podcastId: route.id))
        } else {
            let parsedRoute = AppDeepLinkHelper().parse(url: card.url)
            FlareLog.error("TimelineStatusViewV2 Error: Could not parse Podcast URL from card: \(card.url). Parsed type: \(type(of: parsedRoute)) Optional value: \(String(describing: parsedRoute))")
            // 降级处理：使用系统URL打开
            if let url = URL(string: card.url) {
                openURL(url)
            }
        }
    }

    // MARK: - 辅助方法

    /// 从TimelineItem创建MicroBlogKey
    private func createMicroBlogKey(from item: TimelineItem) -> MicroBlogKey {
        // 从platformType推断host
        let host = extractHostFromPlatformType(item.platformType)
        return MicroBlogKey(id: item.id, host: host)
    }

    /// 从platformType提取host信息
    private func extractHostFromPlatformType(_ platformType: String) -> String {
        // 根据platformType推断默认host
        switch platformType.lowercased() {
        case "mastodon":
            return "mastodon.social" // 默认Mastodon实例
        case "bluesky":
            return "bsky.app"
        case "misskey":
            return "misskey.io"
        case "xqt", "twitter":
            return "x.com"
        case "vvo":
            return "weibo.com"
        default:
            return "unknown.host"
        }
    }

    private func handleTimelineAction(_ actionType: TimelineActionType, item: TimelineItem, at index: Int) {
        FlareLog.debug("TimelineView_v2 Handling action \(actionType) for item: \(item.id) at index: \(index)")
        FlareLog.debug("TimelineView_v2 Received updated item state:")
        FlareLog.debug("   - ID: \(item.id)")
        FlareLog.debug("   - Like count: \(item.likeCount)")
        FlareLog.debug("   - Is liked: \(item.isLiked)")
        FlareLog.debug("   - Retweet count: \(item.retweetCount)")
        FlareLog.debug("   - Is retweeted: \(item.isRetweeted)")
        FlareLog.debug("   - Bookmark count: \(item.bookmarkCount)")
        FlareLog.debug("   - Is bookmarked: \(item.isBookmarked)")

        // 🟢 移除多余的Task，直接执行日志记录
        FlareLog.debug("TimelineView_v2 Updating local state for index: \(index)")
        FlareLog.debug("TimelineView_v2 Local state update logged for index: \(index)")
    }

    // MARK: - 高度缓存辅助方法

    /// 获取指定item的缓存高度
    /// - Returns: 缓存的高度值，如果不存在则返回nil
    private func getCachedHeight() -> CGFloat? {
        return TimelineHeightCache.shared.getHeight(for: item.id)
    }

    /// 缓存指定item的高度
    /// - Parameter height: 要缓存的高度值
    private func cacheHeight(_ height: CGFloat) {
        guard height > 0 else {
            FlareLog.debug("TimelineStatusViewV2 Invalid height \(height) for item: \(item.id)")
            return
        }

        TimelineHeightCache.shared.setHeight(height, for: item.id)
        FlareLog.debug("TimelineStatusViewV2 Cached height \(height) for item: \(item.id)")
    }

    // MARK: - 高度预计算辅助方法

    /// 判断是否应该触发预计算
    /// - Parameter index: 当前item索引
    /// - Returns: 是否应该触发预计算
    private func shouldTriggerPreload(at index: Int) -> Bool {
        // 在接近Timeline开始或结束时触发预计算
        // 这里需要获取Timeline总数，暂时使用简化逻辑
        return index < 10 || index % 3 == 0
    }

    /// 触发高度预计算
    /// - Parameter currentIndex: 当前item索引
    private func triggerHeightPreload(at currentIndex: Int) async {
        // 获取屏幕宽度
        let screenWidth = await MainActor.run {
            UIScreen.main.bounds.width
        }

        // 🟢 移除渐进式预计算：data-flow批量计算应该已经处理了所有item
        FlareLog.debug("TimelineStatusViewV2 Item appeared at index: \(currentIndex) (relying on data-flow precomputation)")
    }
}

