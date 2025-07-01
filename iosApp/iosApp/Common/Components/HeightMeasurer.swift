import SwiftUI

/// 高度测量组件
/// 用于测量SwiftUI View的实际渲染高度并通过回调返回
struct HeightMeasurer: View {
    
    // MARK: - Properties
    
    /// 高度测量完成的回调
    let onHeightMeasured: (CGFloat) -> Void
    
    /// 上次测量的高度，用于避免频繁回调
    @State private var lastMeasuredHeight: CGFloat = 0
    
    /// 测量精度阈值，小于此值的变化将被忽略
    private let measurementThreshold: CGFloat = 1.0
    
    /// 最小有效高度
    private let minimumValidHeight: CGFloat = 10.0
    
    /// 最大有效高度
    private let maximumValidHeight: CGFloat = 3000.0
    
    // MARK: - Body
    
    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear {
                    measureHeight(geometry.size.height)
                }
                .onChange(of: geometry.size.height) { newHeight in
                    measureHeight(newHeight)
                }
        }
    }
    
    // MARK: - Private Methods
    
    /// 测量并验证高度
    /// - Parameter height: 几何读取器提供的高度值
    private func measureHeight(_ height: CGFloat) {
        // 验证高度值的合理性
        guard isValidHeight(height) else {
            FlareLog.debug("HeightMeasurer Invalid height detected: \(height)")
            return
        }
        
        // 检查是否有显著变化
        guard hasSignificantChange(height) else {
            return
        }
        
        // 更新记录并触发回调
        lastMeasuredHeight = height
        onHeightMeasured(height)
        
        FlareLog.debug("HeightMeasurer Measured height: \(height)")
    }
    
    /// 验证高度值是否有效
    /// - Parameter height: 要验证的高度值
    /// - Returns: 是否为有效高度
    private func isValidHeight(_ height: CGFloat) -> Bool {
        // 检查是否为有限数值
        guard height.isFinite && !height.isNaN else {
            return false
        }
        
        // 检查是否在合理范围内
        guard height >= minimumValidHeight && height <= maximumValidHeight else {
            return false
        }
        
        return true
    }
    
    /// 检查高度变化是否显著
    /// - Parameter newHeight: 新的高度值
    /// - Returns: 是否有显著变化
    private func hasSignificantChange(_ newHeight: CGFloat) -> Bool {
        let heightDifference = abs(newHeight - lastMeasuredHeight)
        return heightDifference >= measurementThreshold
    }
}

// MARK: - Preview

#if DEBUG
struct HeightMeasurer_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Sample Content")
                .padding()
                .background(Color.blue.opacity(0.2))
                .background(
                    HeightMeasurer { height in
                        print("Measured height: \(height)")
                    }
                )
            
            Text("Another Content")
                .padding()
                .background(Color.green.opacity(0.2))
                .background(
                    HeightMeasurer { height in
                        print("Measured height: \(height)")
                    }
                )
        }
        .padding()
    }
}
#endif

// MARK: - HeightMeasurer Extensions

extension HeightMeasurer {
    
    /// 创建带有调试信息的高度测量器
    /// - Parameters:
    ///   - identifier: 用于调试的标识符
    ///   - onHeightMeasured: 高度测量回调
    /// - Returns: 配置好的HeightMeasurer
    static func withDebugInfo(
        identifier: String,
        onHeightMeasured: @escaping (CGFloat) -> Void
    ) -> HeightMeasurer {
        return HeightMeasurer { height in
            FlareLog.debug("HeightMeasurer [\(identifier)] Measured height: \(height)")
            onHeightMeasured(height)
        }
    }
    
    /// 创建带有延迟回调的高度测量器
    /// - Parameters:
    ///   - delay: 延迟时间（秒）
    ///   - onHeightMeasured: 高度测量回调
    /// - Returns: 配置好的HeightMeasurer
    static func withDelay(
        _ delay: TimeInterval,
        onHeightMeasured: @escaping (CGFloat) -> Void
    ) -> HeightMeasurer {
        return HeightMeasurer { height in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                onHeightMeasured(height)
            }
        }
    }
}

// MARK: - View Extension for Height Measurement

extension View {
    
    /// 为View添加高度测量功能
    /// - Parameter onHeightMeasured: 高度测量完成的回调
    /// - Returns: 添加了高度测量功能的View
    func measureHeight(onHeightMeasured: @escaping (CGFloat) -> Void) -> some View {
        self.background(
            HeightMeasurer(onHeightMeasured: onHeightMeasured)
        )
    }
    
    /// 为View添加带标识符的高度测量功能
    /// - Parameters:
    ///   - identifier: 用于调试的标识符
    ///   - onHeightMeasured: 高度测量完成的回调
    /// - Returns: 添加了高度测量功能的View
    func measureHeight(
        identifier: String,
        onHeightMeasured: @escaping (CGFloat) -> Void
    ) -> some View {
        self.background(
            HeightMeasurer.withDebugInfo(
                identifier: identifier,
                onHeightMeasured: onHeightMeasured
            )
        )
    }
}
