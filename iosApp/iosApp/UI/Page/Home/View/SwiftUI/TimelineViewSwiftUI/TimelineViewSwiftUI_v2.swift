
import Combine
import Kingfisher
import shared
import SwiftUI

 struct TimelineViewSwiftUIV2: View {
    let tab: FLTabItem
    @ObservedObject var store: AppBarTabSettingStore
    @Binding var scrollPositionID: String?
    @Binding var scrollToTopTrigger: Bool
     
    let isCurrentTab: Bool
     
     @Binding var showFloatingButton: Bool

     @State private var presenter: TimelinePresenter?

     @State private var stateConverter = PagingStateConverter()

     @State private var timelineState: FlareTimelineState = .loading

     @State private var showErrorAlert = false
     
     @State private var currentError: FlareError?
 
     @State private var cancellables = Set<AnyCancellable>()

     @State private var refreshDebounceTimer: Timer?
     @State private var topVisibleItemID: String? = "top"


    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ScrollToTopView(tabKey: tab.key)
                        .id("top")

                    // 使用简化的状态管理
                    TimelineContentViewV2(
                        state: timelineState,
                        presenter: presenter,
                        scrollPositionID: $scrollPositionID,
                        onError: { error in
                            currentError = error
                            showErrorAlert = true
                        }
                    )
                }
            }
            .scrollPosition(id: $topVisibleItemID)
            .onChange(of: topVisibleItemID) { _, newID in
                handleScrollOffsetChange(newID)
            }
            .onChange(of: scrollToTopTrigger) { _, _ in
                let _ = FlareLog.debug("TimelineView_v2 ScrollToTop trigger changed for tab: \(tab.key)")
                guard isCurrentTab else { return }

                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(ScrollToTopView.Constants.scrollToTop, anchor: .top)
                }
            }
        }
        .refreshable {
            await handleRefresh()
        }
        .task {
            await setupDataSource()
        }
        .onReceive(NotificationCenter.default.publisher(for: .timelineItemUpdated)) { _ in
            FlareLog.debug("TimelineView_v2 Received item update notification for tab: \(tab.key)")

            // 🔥 防抖机制：取消之前的定时器，设置新的定时器
            refreshDebounceTimer?.invalidate()
            refreshDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                // 🟢 SwiftUI View是struct，直接使用局部变量避免循环引用
                guard isCurrentTab else { return }

                Task {
                    await handleRefresh()
                }
            }
        }
        .onDisappear {
            cancellables.removeAll()
            // 🟢 清理Timer，防止内存泄漏
            refreshDebounceTimer?.invalidate()
            refreshDebounceTimer = nil
        }
    }


     private func setupDataSource() async {
        FlareLog.debug("TimelineViewSwiftUI_v2 Setting up direct data flow for tab: \(tab.key)")

         guard let kmpPresenter = store.getOrCreatePresenter(for: tab) else {
            FlareLog.error("TimelineViewSwiftUI_v2 Failed to get presenter for tab: \(tab.key)")
            await MainActor.run {
                timelineState = .error(.data(.parsing))
            }
            return
        }

        await MainActor.run {
            presenter = kmpPresenter

             Task {
                for await state in kmpPresenter.models {
                    await MainActor.run {
                        guard let timelineState = state as? TimelineState else {
                            return
                        }

                        let newState = stateConverter.convert(timelineState.listState)
                        let oldState = self.timelineState

                         if newState != oldState {
                            self.timelineState = newState
                            FlareLog.debug("TimelineViewSwiftUI_v2 State updated: \(newState.description)")

                            // 🟢 在UI更新后异步进行批量高度预计算
                            Task {
                                await performBatchHeightPrecomputation(for: newState)
                            }
                        }
                    }
                }
            }
        }

        FlareLog.debug("TimelineViewSwiftUI_v2 Direct data flow setup completed for tab: \(tab.key)")
    }

     private func handleRefresh() async {
        FlareLog.debug("TimelineViewSwiftUI_v2 Handling refresh for tab: \(tab.key)")

        guard let presenter else {
            FlareLog.warning("TimelineViewSwiftUI_v2 No presenter available for refresh")
            return
        }

        do {
            // 重置转换器状态
            stateConverter.reset()

            // 直接调用KMP的刷新方法
            let timelineState = presenter.models.value
            if let timelineState = timelineState as? TimelineState {
                try await timelineState.refresh()
            }
            FlareLog.debug("TimelineViewSwiftUI_v2 Refresh completed for tab: \(tab.key)")
        } catch {
            FlareLog.error("TimelineViewSwiftUI_v2 Refresh failed: \(error)")
        }
    }

    private func handleScrollOffsetChange(_ newID: String?) {
        showFloatingButton = (newID != "top")
    }

    // MARK: - 批量高度预计算

    /// 在数据获取完成后、UI展示前进行批量高度预计算
    /// - Parameter state: 新的Timeline状态
    private func performBatchHeightPrecomputation(for state: FlareTimelineState) async {
        // 只对loaded状态进行预计算
        guard case let .loaded(items, _, _) = state else {
            return
        }

        // 避免对空数据或过少数据进行预计算
        guard items.count > 0 else {
            return
        }

        FlareLog.debug("TimelineViewSwiftUI_v2 Starting batch height precomputation for \(items.count) items")

        // 🟢 异步执行批量预计算，不阻塞UI更新
        Task.detached(priority: .utility) {
            await TimelineHeightPreloader.shared.batchPreloadHeights(
                for: items,
                screenWidth: await UIScreen.main.bounds.width
            )
            // 🟢 移除重复的耗时计算，TimelineHeightPreloader内部已有详细的耗时监控
        }
    }
}







