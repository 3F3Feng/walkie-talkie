import SwiftUI
import Core
import Bridge

/// Talk mode for walkie talkie
public enum TalkMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case ptt = "ptt"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .auto: return "自动"
        case .ptt: return "手动 (PTT)"
        }
    }
}

struct ContentView: View {
    @StateObject private var bridge = WalkieCoreBridge.shared
    @State private var selectedTalkMode: TalkMode = .auto
    @State private var isPairingMode: Bool = false
    
    var body: some View {
        NavigationView {
            List {
                Section("发现设备") {
                    ForEach(bridge.walkieDevices()) { device in
                        DeviceRow(device: device.asTrackedDevice)
                    }
                }
                
                Section("配对") {
                    Toggle("配对模式", isOn: $isPairingMode)
                        .onChange(of: isPairingMode) { newValue in
                            if newValue {
                                bridge.startPairingMode()
                            } else {
                                bridge.stopPairingMode()
                            }
                        }
                }
                
                Section("对讲") {
                    Picker("模式", selection: $selectedTalkMode) {
                        Text("自动").tag(TalkMode.auto)
                        Text("手动").tag(TalkMode.ptt)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("WalkieTalkie")
        }
    }
}

struct DeviceRow: View {
    let device: TrackedDevice
    
    var body: some View {
        HStack {
            Text(device.displayName)
            Spacer()
            Text("\(String(format: "%.1f", device.distance))m")
                .foregroundColor(.secondary)
        }
    }
}
