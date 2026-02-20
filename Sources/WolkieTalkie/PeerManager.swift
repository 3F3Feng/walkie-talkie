// MARK: - PeerManager (已迁移到 ProximityManager)
// 此文件仅用于保持 Xcode 项目引用兼容
// 所有功能已迁移到 ProximityManager

import Foundation
import MultipeerConnectivity

/// @deprecated 请使用 ProximityManager 代替
@available(*, deprecated, message: "请使用 ProximityManager 代替")
class PeerManager {
    static let shared = ProximityManager.shared
}
