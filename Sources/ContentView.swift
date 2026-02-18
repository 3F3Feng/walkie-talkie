import SwiftUI
import NearbyInteraction
import AVFoundation

// MARK: - 主界面
struct ContentView: View {
    @StateObject private var proximityManager = ProximityManager.shared
    
    var body: some View {
        ZStack {
            // 背景渐变
            backgroundGradient
            
            VStack(spacing: 0) {
                // 顶部状态栏
                statusBar
                
                Spacer()
                
                // 核心内容区
                mainContent
                
                Spacer()
                
                // 控制按钮
                controlPanel
            }
            .padding()
        }
    }
    
    // MARK: - 背景
    private var backgroundGradient: some View {
        LinearGradient(
            colors: [backgroundColor, Color.black.opacity(0.9)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    private var backgroundColor: Color {
        switch proximityManager.state {
        case .connected, .transmitting:
            return Color.green.opacity(0.1)
        case .discovering:
            return Color.blue.opacity(0.1)
        case .error:
            return Color.red.opacity(0.1)
        default:
            return Color.gray.opacity(0.1)
        }
    }
    
    // MARK: - 状态栏
    private var statusBar: some View {
        HStack {
            // U1 芯片状态
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.green)
                Text("U1")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.2))
            .cornerRadius(20)
            
            Spacer()
            
            // 应用状态
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(proximityManager.state.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.2))
            .cornerRadius(20)
        }
        .foregroundColor(.white)
    }
    
    private var statusColor: Color {
        switch proximityManager.state {
        case .connected: return .green
        case .discovering: return .blue
        case .transmitting: return .orange
        case .error: return .red
        default: return .gray
        }
    }
    
    // MARK: - 主内容区
    private var mainContent: some View {
        VStack(spacing: 30) {
            // 距离显示卡片
            distanceCard
            
            // 音量显示
            volumeCard
        }
    }
    
    private var distanceCard: some View {
        VStack(spacing: 16) {
            // 距离数值
            HStack(alignment: .center, spacing: 4) {
                Text(String(format: "%.2f", proximityManager.currentDistance))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("m")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
            
            // 距离等级标签
            if proximityManager.currentDistance > 0 {
                Text(proximityManager.distanceLevel.rawValue)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(distanceLevelColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(distanceLevelColor.opacity(0.2))
                    .cornerRadius(8)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(distanceLevelColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var distanceLevelColor: Color {
        switch proximityManager.distanceLevel {
        case .veryNear: return .red
        case .near: return .orange
        case .medium: return .yellow
        case .far: return .green
        case .veryFar: return .blue
        case .unknown: return .gray
        }
    }
    
    private var volumeCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "speaker.wave.1")
                    .foregroundColor(.gray)
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // 背景轨道
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 8)
                        
                        // 音量填充
                        RoundedRectangle(cornerRadius: 4)
                            .fill(volumeGradient)
                            .frame(width: CGFloat(proximityManager.currentVolume) * geometry.size.width, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: proximityManager.currentVolume)
                    }
                }
                .frame(height: 8)
                
                Image(systemName: "speaker.wave.3")
                    .foregroundColor(.white)
            }
            
            HStack {
                Text("音量")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Text("\(Int(proximityManager.currentVolume * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    private var volumeGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    // MARK: - 控制面板
    private var controlPanel: some View {
        VStack(spacing: 20) {
            // 主按钮
            mainButton
            
            // 参数调节区
            parameterControls
        }
    }
    
    private var mainButton: some View {
        Button(action: toggleWalkieTalkie) {
            HStack(spacing: 12) {
                Image(systemName: buttonIcon)
                    .font(.title2)
                Text(buttonText)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: buttonColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: buttonColors[0].opacity(0.4), radius: 10, x: 0, y: 4)
        }
        .disabled(proximityManager.state == .discovering)
        .animation(.easeInOut(duration: 0.2), value: proximityManager.state)
    }
    
    private var buttonIcon: String {
        switch proximityManager.state {
        case .idle: return "play.fill"
        case .discovering: return "antenna.radiowaves.left.and.right"
        case .connected: return "stop.fill"
        case .transmitting: return "mic.fill"
        case .error: return "exclamationmark.triangle"
        }
    }
    
    private var buttonText: String {
        switch proximityManager.state {
        case .idle: return "开始对讲"
        case .discovering: return "发现中..."
        case .connected, .transmitting: return "停止对讲"
        case .error: return "重试"
        }
    }
    
    private var buttonColors: [Color] {
        switch proximityManager.state {
        case .idle: return [.green, .green.opacity(0.8)]
        case .discovering: return [.blue, .blue.opacity(0.8)]
        case .connected: return [.red, .red.opacity(0.8)]
        case .error: return [.orange, .orange.opacity(0.8)]
        default: return [.gray, .gray.opacity(0.8)]
        }
    }
    
    private var parameterControls: some View {
        VStack(spacing: 12) {
            // 滑块标题
            HStack {
                Text("参数设置")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            
            // 最小距离
            VStack(spacing: 4) {
                HStack {
                    Text("有效距离范围")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(Int(proximityManager.minDistance))m - \(Int(proximityManager.maxDistance))m")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Slider(value: .init(
                    get: { Double(proximityManager.maxDistance) },
                    set: { proximityManager.maxDistance = $0 }
                ), in: 5...30, step: 1)
                .tint(.blue)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - 动作
    private func toggleWalkieTalkie() {
        if proximityManager.state == .idle || proximityManager.state == .error {
            proximityManager.startWalkieTalkie()
        } else {
            proximityManager.stopWalkieTalkie()
        }
    }
}

// MARK: - 预览
#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
