import SwiftUI
import NearbyInteraction
import simd

// MARK: - 雷达视图
/// 使用 UWB 方向数据 (azimuth/elevation) 可视化显示对端位置
struct RadarView: View {
    @ObservedObject var proximityManager: ProximityManager
    
    // 雷达配置
    var radarSize: CGFloat = 280
    var maxRange: Double = 10.0 // 最大显示距离（米）
    
    // 距离圆环
    private let rangeRings: [Double] = [2, 4, 6, 8, 10]
    
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            
            ZStack {
                // 背景圆盘
                Circle()
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        Circle()
                            .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    )
                
                // 距离圆环
                ForEach(rangeRings, id: \.self) { ring in
                    Circle()
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                        .frame(width: size * CGFloat(ring / maxRange), height: size * CGFloat(ring / maxRange))
                }
                
                // 十字准线
                CrosshairView(center: center, size: size)
                    .stroke(Color.green.opacity(0.3), lineWidth: 1)
                
                // 对端位置指示器
                PeerIndicator(
                    distance: proximityManager.currentDistance,
                    direction: UWBProximityProvider.shared.direction,
                    maxRange: maxRange,
                    center: center,
                    containerSize: size
                )
                
                // 中心点（本机位置）
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                
                // 方向指示
                DirectionLabels(center: center, size: size)
                
                // 距离信息显示
                VStack(spacing: 4) {
                    Spacer()
                    Text("\(String(format: "%.2f", proximityManager.currentDistance))m")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    
                    if let direction = UWBProximityProvider.shared.direction {
                        let azimuth = calculateAzimuth(direction)
                        let elevation = calculateElevation(direction)
                        Text("Az: \(String(format: "%.0f°", azimuth))  El: \(String(format: "%.0f°", elevation))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    } else {
                        Text("方向校准中...")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    /// 计算方位角 (azimuth)
    private func calculateAzimuth(_ direction: simd_float3) -> Float {
        let azimuth = atan2(direction.y, direction.x) * 180 / .pi
        return azimuth
    }
    
    /// 计算仰角 (elevation)
    private func calculateElevation(_ direction: simd_float3) -> Float {
        let horizontal = sqrt(direction.x * direction.x + direction.y * direction.y)
        let elevation = atan2(direction.z, horizontal) * 180 / .pi
        return elevation
    }
}

// MARK: - 十字准线视图
struct CrosshairView: Shape {
    let center: CGPoint
    let size: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let halfSize = size / 2
        
        path.move(to: CGPoint(x: center.x - halfSize, y: center.y))
        path.addLine(to: CGPoint(x: center.x + halfSize, y: center.y))
        
        path.move(to: CGPoint(x: center.x, y: center.y - halfSize))
        path.addLine(to: CGPoint(x: center.x, y: center.y + halfSize))
        
        return path
    }
}

// MARK: - 对端位置指示器
struct PeerIndicator: View {
    let distance: Double
    let direction: simd_float3?
    let maxRange: Double
    let center: CGPoint
    let containerSize: CGFloat
    
    var body: some View {
        if let direction = direction, distance > 0 {
            let position = calculatePosition(direction: direction, distance: distance)
            
            ZStack {
                SignalRipple(position: position)
                
                Circle()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: .red.opacity(0.5), radius: 8)
                    .position(position)
                
                DirectionLine(from: center, to: position)
                    .stroke(Color.red.opacity(0.5), lineWidth: 2)
            }
        } else {
            Text("等待方向数据...")
                .font(.caption)
                .foregroundColor(.gray)
                .position(center)
        }
    }
    
    private func calculatePosition(direction: simd_float3, distance: Double) -> CGPoint {
        let normalizedDistance = min(distance / maxRange, 1.0)
        let azimuth = atan2(direction.y, direction.x)
        
        let maxRadius = containerSize * 0.45
        let radius = CGFloat(normalizedDistance) * maxRadius
        
        let x = center.x + radius * CGFloat(cos(azimuth))
        let y = center.y + radius * CGFloat(sin(azimuth))
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - 信号波纹动画
struct SignalRipple: View {
    let position: CGPoint
    @State private var animating: Bool = false
    
    var body: some View {
        Circle()
            .stroke(Color.red.opacity(0.3), lineWidth: 2)
            .frame(width: animating ? 60 : 20, height: animating ? 60 : 20)
            .position(position)
            .onAppear {
                withAnimation(Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

// MARK: - 方向线
struct DirectionLine: Shape {
    let from: CGPoint
    let to: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }
}

// MARK: - 方向标签
struct DirectionLabels: View {
    let center: CGPoint
    let size: CGFloat
    
    var body: some View {
        Group {
            Text("N")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green.opacity(0.6))
                .position(x: center.x, y: center.y - size * 0.48)
            
            Text("S")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.red.opacity(0.6))
                .position(x: center.x, y: center.y + size * 0.48)
            
            Text("E")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green.opacity(0.6))
                .position(x: center.x + size * 0.48, y: center.y)
            
            Text("W")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.green.opacity(0.6))
                .position(x: center.x - size * 0.48, y: center.y)
        }
    }
}

// MARK: - 预览
#Preview {
    RadarView(proximityManager: ProximityManager.shared)
        .frame(width: 300, height: 300)
        .preferredColorScheme(.dark)
}
