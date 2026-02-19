// 修复后的关键函数

// MARK: - 配对消息处理
private func handlePairingAccept(_ message: PeerMessage, from peerID: MCPeerID) {
    guard let deviceName = message.payload?["deviceName"] else { return }
    print("[Manager] ✅ Pairing accepted by: \(deviceName)")
    
    if let device = activeDevices.first(where: { $0.id == peerID.displayName }) {
        device.pairingState = .paired
        device.connectionState = .connected
        savePairedDevice(device)
        
        // 确保 pairedDevices 包含这个设备
        if !pairedDevices.contains(where: { $0.id == device.id }) {
            pairedDevices.append(device)
        }
        
        // 通知 UI 更新
        let updatedPairedDevices = pairedDevices
        DispatchQueue.main.async {
            self.pairedDevices = updatedPairedDevices
        }
    }
    
    // 清除待处理请求
    DispatchQueue.main.async {
        self.pendingPairingRequest = nil
    }
}

/// 清理未配对的设备（改进版 - 不删除已配对设备）
private func cleanupUnpairedDevices() {
    // 只保留已配对的设备
    let pairedIds = Set(pairedDevices.map { $0.id })
    
    // 过滤活跃设备：只保留已配对的
    activeDevices.removeAll { device in
        !pairedIds.contains(device.id)
    }
    
    // 清理可发现设备：移除未配对的和已超时未连接的
    discoverableDevices.removeAll { device in
        !pairedIds.contains(device.id) && device.connectionState != .connected
    }
    
    // 确保所有已配对设备都在 activeDevices 中
    for pairedDevice in pairedDevices {
        if !activeDevices.contains(where: { $0.id == pairedDevice.id }) {
            activeDevices.append(pairedDevice)
        }
    }
    
    print("[Manager] Cleaned up - Active: \(activeDevices.count), Paired: \(pairedDevices.count), Discoverable: \(discoverableDevices.count)")
}

/// 切换配对模式（修复版）
func togglePairingMode() {
    // 在主线程执行，避免 UI 卡顿
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        
        self.isPairingMode.toggle()
        print("[Manager] Pairing mode: \(self.isPairingMode ? "ON" : "OFF")")
        
        if self.isPairingMode {
            self.appMode = .pairing
            // 如果会话未启动，先启动（异步，避免阻塞主线程）
            if self.state == .idle || self.state == .error {
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    self?.startWalkieTalkie()
                }
            }
        } else {
            self.appMode = .talk
            // 切换到对话模式时，清理未配对的发现设备（在主线程）
            self.cleanupUnpairedDevices()
        }
    }
}

/// 停止对讲（改进版 - 保留配对状态）
func stopWalkieTalkie() {
    uwbProvider.stop()
    bluetoothProvider.stop()
    stopMultipeerSession()
    stopAudioEngine()
    
    // 重置所有设备的距离平滑器
    for smoother in distanceSmoothers.values {
        smoother.reset()
    }
    distanceSmoothers.removeAll()
    
    // 只清理可发现设备，保留已配对设备
    discoverableDevices.removeAll()
    
    // 保留已配对设备，但重置它们的状态
    for device in pairedDevices {
        device.distance = 0.0
        device.distanceLevel = .unknown
        device.connectionState = .disconnected
    }
    
    // 清空活跃设备（但保留配对关系）
    activeDevices.removeAll { device in
        !pairedDevices.contains(where: { $0.id == device.id })
    }
    
    // 重置状态
    currentDistance = 0.0
    currentVolume = 0.5
    tokenExchangeCompleted = false
    currentPeerID = nil
    providerType = .bluetooth
    tokenExchangeState = .idle
    
    // 清理 Token
    receivedTokens.removeAll()
    invalidateTokenExchangeTimer()
    
    errorMessage = nil
    transition(to: .idle)
    print("[Manager] WalkieTalkie stopped, paired devices preserved: \(pairedDevices.count)")
}

/// 保存已配对设备到持久化存储（改进版）
private func savePairedDevice(_ device: TrackedDevice) {
    var names = UserDefaults.standard.stringArray(forKey: "pairedDeviceNames") ?? []
    
    // 只有新设备才保存
    if !names.contains(device.displayName) {
        names.append(device.displayName)
        UserDefaults.standard.set(names, forKey: "pairedDeviceNames")
        print("[Manager] Saved paired device: \(device.displayName)")
    }
    
    // 确保 pairedDevices 数组包含这个设备
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        if !self.pairedDevices.contains(where: { $0.id == device.id }) {
            self.pairedDevices.append(device)
            print("[Manager] Added to pairedDevices array: \(device.displayName)")
        }
    }
}

/// 加载已配对设备（改进版 - 同时恢复连接状态）
func loadPairedDevices() {
    let names = UserDefaults.standard.stringArray(forKey: "pairedDeviceNames") ?? []
    
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        
        self.pairedDevices = names.map { name in
            let device = TrackedDevice(displayName: name)
            device.pairingState = .paired
            return device
        }
        
        // 同时加载到 activeDevices 中，这样它们会显示在设备列表里
        for device in self.pairedDevices {
            if !self.activeDevices.contains(where: { $0.id == device.id }) {
                self.activeDevices.append(device)
            }
        }
        
        print("[Manager] Loaded \(self.pairedDevices.count) paired devices and restored to active list")
    }
}
