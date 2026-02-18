import SwiftUI
import AVFoundation
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
    // 应用启动时配置
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        print("[App] Launching WalkieTalkie...")
        
        // 1. 配置音频会话
        configureAudioSession()
        
        // 2. 配置日志
        configureLogging()
        
        // 3. 检查设备和授权状态
        checkDeviceCapabilities()
        
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // 应用进入后台时暂停 UWB
        print("[App] Application will resign active")
        ProximityManager.shared.stopWalkieTalkie()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // 应用回到前台
        print("[App] Application did become active")
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // 应用关闭时清理
        print("[App] Application will terminate")
        ProximityManager.shared.stopWalkieTalkie()
    }
    
    // MARK: - 配置音频会话
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 配置为对讲模式
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [
                    .allowBluetooth,      // 允许蓝牙耳机
                    .allowAirPlay,        // 允许 AirPlay
                    .defaultToSpeaker,    // 默认扬声器输出
                    .mixWithOthers        // 允许与其他应用混音
                ]
            )
            
            // 设置采样率和缓冲区
            try session.setPreferredSampleRate(44100.0)
            try session.setPreferredIOBufferDuration(0.005)
            
            // 激活会话
            try session.setActive(true)
            
            // 监听音频路由变化
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleRouteChange),
                name: AVAudioSession.routeChangeNotification,
                object: nil
            )
            
            // 监听音频中断
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            
            print("[Audio] Session configured successfully")
            print("[Audio] Sample rate: \(session.sampleRate)")
            print("[Audio] IO buffer duration: \(session.ioBufferDuration)")
            
        } catch {
            print("[Audio] Configuration failed: \(error)")
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .newDeviceAvailable:
            let session = AVAudioSession.sharedInstance()
            if session.currentRoute.outputs.first?.portType == .builtInSpeaker {
                print("[Audio] Switched to speaker")
            }
            for output in session.currentRoute.outputs where output.portType == .headphones {
                print("[Audio] Headphones connected")
                break
            }
        case .oldDeviceUnavailable:
            print("[Audio] Audio device disconnected")
        default:
            break
        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        if type == .began {
            print("[Audio] Interruption began (e.g., phone call)")
            ProximityManager.shared.stopWalkieTalkie()
        } else if type == .ended {
            print("[Audio] Interruption ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    print("[Audio] Should resume")
                }
            }
        }
    }
    
    // MARK: - 配置日志
    
    private func configureLogging() {
        #if DEBUG
        print("[App] Debug mode enabled")
        // 启用详细的 NearbyInteraction 日志
        UserDefaults.standard.set(true, forKey: "NI_DEBUG_MODE")
        #endif
    }
    
    // MARK: - 检查设备能力
    
    private func checkDeviceCapabilities() {
        // 检查 U1 芯片支持
        let uwbAvailable = NearbyInteraction.NISession.isSupported
        print("[Device] UWB supported: \(uwbAvailable)")
        
        // 检查蓝牙状态
        let bluetoothAvailable = checkBluetoothAvailability()
        print("[Device] Bluetooth available: \(bluetoothAvailable)")
        
        if !uwbAvailable && !bluetoothAvailable {
            print("[Device] ⚠️ Neither UWB nor Bluetooth available")
        }
    }
    
    private func checkBluetoothAvailability() -> Bool {
        // 实际检查由 CoreBluetooth 完成
        return true
    }
}

// MARK: - 应用入口点
@main
struct WalkieTalkieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
