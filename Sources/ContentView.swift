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
                
                // 模式选择器
                modeSelector
                    .padding(.horizontal)
                    .padding(.top, 8)
                
                // 核心内容区 - 设备列表
                deviceListContent
                
                Spacer()
                
                // 控制按钮
                controlPanel
            }
            .padding()
        }
        .sheet(isPresented: Binding<Bool>(
            get: { proximityManager.pendingPairingRequest != nil },
            set: { if !$0 { proximityManager.pendingPairingRequest = nil } }
        )) {
            if let device = proximityManager.pendingPairingRequest {
                VStack(spacing: 20) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("配对请求")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("「\(device.displayName)」请求与您配对")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            proximityManager.acceptPairing(with: device)
                        }) {
                            Text("接受")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                        
                        Button(action: {
                            proximityManager.rejectPairing(with: device)
                        }) {
                            Text("拒绝")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
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
            // UWB 状态
            HStack(spacing: 6) {
                Image(systemName: proximityManager.uwbAvailable ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(proximityManager.uwbAvailable ? .green : .orange)
                Text(proximityManager.uwbAvailable ? "UWB" : "BT")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(proximityManager.uwbAvailable ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .cornerRadius(20)
            
            Spacer()
            
            // 设备数量
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                Text("\(proximityManager.activeDevices.count) 已连")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.2))
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
    
    // MARK: - 模式选择器
    private var modeSelector: some View {
        VStack(spacing: 12) {
            // 配对模式开关
            HStack {
                Image(systemName: "link.badge.plus")
                    .foregroundColor(proximityManager.isPairingMode ? .blue : .gray)
                Text("配对模式")
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { proximityManager.isPairingMode },
                    set: { _ in proximityManager.togglePairingMode() }
                ))
                .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            
            // 对话模式切换（始终显示）
            HStack {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.green)
                    Text("对话模式")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Picker("模式", selection: $proximityManager.talkMode) {
                        Text("自动").tag(TalkMode.auto)
                        Text("按键说话").tag(TalkMode.ptt)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
            
            // 模式提示
            Text(proximityManager.isPairingMode ? "正在搜索附近设备..." : "与已配对设备对话中")
                .font(.caption)
                .foregroundColor(.gray)
        }
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
    
    // MARK: - 设备列表内容
    @ViewBuilder
    private var deviceListContent: some View {
        if proximityManager.activeDevices.isEmpty && proximityManager.discoverableDevices.isEmpty {
            // 空状态
            emptyStateView
        } else {
            // 设备列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    // 已连接设备
                    if !proximityManager.activeDevices.isEmpty {
                        Section {
                            ForEach(proximityManager.activeDevices) { device in
                                ConnectedDeviceCard(device: device)
                            }
                        } header: {
                            SectionHeader(title: "已连接设备", icon: "checkmark.circle.fill")
                        }
                    }
                    
                    // 可发现设备（Walkie置顶，其他按距离排序）
                    let walkieDevices = proximityManager.discoverableDevices.filter { $0.displayName.lowercased().contains("walkie") }.sorted { $0.distance < $1.distance }
                    let otherDevices = proximityManager.discoverableDevices.filter { !$0.displayName.lowercased().contains("walkie") }.sorted { $0.distance < $1.distance }
                    let sortedDevices = walkieDevices + otherDevices
                    
                    if !sortedDevices.isEmpty {
                        Section {
                            ForEach(sortedDevices) { device in
                                DiscoverableDeviceCard(device: device)
                            }
                        } header: {
                            SectionHeader(title: "可发现设备", icon: "antenna.radiowaves.left.and.right")
                        }
                    }
                    
                    // 错误/警告消息
                    if let errorMsg = proximityManager.errorMessage {
                        errorBanner(message: errorMsg)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: proximityManager.state == .discovering ? "antenna.radiowaves.left.and.right" : "iphone")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text(proximityManager.state == .discovering ? "正在搜索附近设备..." : "点击「开始对讲」搜索设备")
                .font(.body)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(12)
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
        case .connected, .transmitting: return "stop.fill"
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
            HStack {
                Text("参数设置")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }
            
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

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.gray)
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - 已连接设备卡片
struct ConnectedDeviceCard: View {
    @ObservedObject var device: TrackedDevice
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // 设备图标
                Image(systemName: device.providerType == .uwb ? "antenna.radiowaves.left.and.right" : "wave.3.right")
                    .font(.title2)
                    .foregroundColor(device.providerType == .uwb ? .green : .orange)
                    .frame(width: 40)
                
                // 设备信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Text(device.providerType.rawValue)
                            .font(.caption2)
                            .foregroundColor(.gray)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(device.connectionState.displayText)
                            .font(.caption2)
                            .foregroundColor(connectionStateColor)
                    }
                }
                
                Spacer()
                
                // 距离显示
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .center, spacing: 2) {
                        Text(String(format: "%.2f", device.distance))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("m")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Text(device.distanceLevel.rawValue)
                        .font(.caption2)
                        .foregroundColor(distanceLevelColor)
                }
            }
            
            // 音量条
            if device.distance > 0 {
                VolumeBar(volume: device.volume)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(distanceLevelColor.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private var connectionStateColor: Color {
        switch device.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        }
    }
    
    private var distanceLevelColor: Color {
        switch device.distanceLevel {
        case .veryNear: return .red
        case .near: return .orange
        case .medium: return .yellow
        case .far: return .green
        case .veryFar: return .blue
        case .unknown: return .gray
        }
    }
}

// MARK: - 可发现设备卡片
struct DiscoverableDeviceCard: View {
    @ObservedObject var device: TrackedDevice
    @StateObject private var manager = ProximityManager.shared
    
    var body: some View {
        HStack {
            // 设备图标
            Image(systemName: device.providerType == .uwb ? "antenna.radiowaves.left.and.right" : "wave.3.right")
                .font(.title2)
                .foregroundColor(device.providerType == .uwb ? .green : .blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                HStack(spacing: 4) {
                    // 距离
                    if device.distance > 0 {
                        Text(String(format: "%.1fm", device.distance))
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    
                    // 配对状态
                    if device.pairingState == .paired {
                        Text("已配对")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            // 配对按钮（仅未配对时显示）
            if device.pairingState != .paired {
                Button(action: {
                    manager.requestPairing(with: device)
                }) {
                    Text("配对")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
}

// MARK: - 音量条
struct VolumeBar: View {
    let volume: Float
    
    var body: some View {
        HStack {
            Image(systemName: "speaker.fill")
                .font(.caption2)
                .foregroundColor(.gray)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(volumeGradient)
                        .frame(width: CGFloat(volume) * geometry.size.width, height: 4)
                }
            }
            .frame(height: 4)
            
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption2)
                .foregroundColor(.white)
            
            Text("\(Int(volume * 100))%")
                .font(.caption2)
                .foregroundColor(.gray)
                .frame(width: 35, alignment: .trailing)
        }
    }
    
    private var volumeGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - 预览
#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
