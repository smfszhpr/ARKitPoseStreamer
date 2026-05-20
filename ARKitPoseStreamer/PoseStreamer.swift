import ARKit
import Network
import simd
import Combine

class PoseStreamer: NSObject, ObservableObject, ARSessionDelegate {

    // MARK: - Published 状态 (供 UI 使用)
    @Published var isStreaming: Bool = false
    @Published var statusText: String = "未开始"
    @Published var fps: Int = 0
    @Published var packetsSent: Int = 0

    // MARK: - 配置
    var targetIP: String = "192.168.1.100"
    var targetPort: UInt16 = 9999
    var handSide: UInt8 = 1  // 0=左手, 1=右手

    // MARK: - 内部状态
    let arSession = ARSession()
    private var connection: NWConnection?
    private var seq: UInt32 = 0
    private var frameCount: Int = 0
    private var lastFPSTime: Date = Date()

    override init() {
        super.init()
        arSession.delegate = self
    }

    // MARK: - 启动/停止

    func start(ip: String, port: UInt16, side: UInt8) {
        self.targetIP = ip
        self.targetPort = port
        self.handSide = side
        self.seq = 0
        self.frameCount = 0
        self.lastFPSTime = Date()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let params = NWParameters.udp
        params.prohibitedInterfaceTypes = []
        connection = NWConnection(to: endpoint, using: params)
        connection?.start(queue: .global(qos: .userInteractive))

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity
        arSession.run(config, options: [.resetTracking, .removeExistingAnchors])

        DispatchQueue.main.async {
            self.isStreaming = true
            self.statusText = "正在推流到 \(ip):\(port)"
        }
    }

    func stop() {
        arSession.pause()
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async {
            self.isStreaming = false
            self.statusText = "已停止"
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let conn = connection else { return }

        switch frame.camera.trackingState {
        case .normal:
            break
        case .limited(let reason):
            let reasonStr: String
            switch reason {
            case .initializing: reasonStr = "初始化中"
            case .excessiveMotion: reasonStr = "移动过快"
            case .insufficientFeatures: reasonStr = "特征点不足(光线/纹理)"
            case .relocalizing: reasonStr = "重定位中"
            @unknown default: reasonStr = "未知"
            }
            DispatchQueue.main.async {
                self.statusText = "⚠️ ARKit 追踪受限: \(reasonStr) — 暂停发送"
            }
            return
        case .notAvailable:
            DispatchQueue.main.async {
                self.statusText = "❌ ARKit 追踪不可用 — 暂停发送"
            }
            return
        }

        let transform = frame.camera.transform
        let pos = SIMD3<Float>(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
        let rotMatrix = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        let quat = simd_quaternion(rotMatrix)

        var packet = Data(capacity: 37)
        packet.append(contentsOf: [0x41, 0x52, 0x4B, 0x54])
        packet.append(handSide)

        var s = seq.littleEndian
        packet.append(contentsOf: withUnsafeBytes(of: &s) { Array($0) })
        seq &+= 1

        var floats: [Float] = [
            pos.x, pos.y, pos.z,
            quat.imag.x, quat.imag.y, quat.imag.z, quat.real
        ]
        floats.withUnsafeBytes { ptr in
            packet.append(contentsOf: ptr)
        }

        conn.send(content: packet, completion: .idempotent)

        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSTime)
        if elapsed >= 1.0 {
            let currentFPS = Int(Double(frameCount) / elapsed)
            let sent = packetsSent + frameCount
            DispatchQueue.main.async {
                self.fps = currentFPS
                self.packetsSent = sent
                self.statusText = "推流中 → \(self.targetIP):\(self.targetPort) | \(currentFPS) FPS | \(sent) 包"
            }
            frameCount = 0
            lastFPSTime = now
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusText = "ARKit 错误: \(error.localizedDescription)"
            self.isStreaming = false
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusText = "ARKit 被中断（切到后台？）"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusText = "ARKit 恢复，正在重新定位..."
        }
    }
}
