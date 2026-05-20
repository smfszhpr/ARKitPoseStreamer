// ContentView.swift
// 主界面：AR 相机预览 + 配置 + 状态

import SwiftUI
import ARKit
import RealityKit

struct ContentView: View {
    @StateObject private var streamer = PoseStreamer()

    @State private var ipAddress: String = "192.168.1.100"
    @State private var portStr: String = "9999"
    @State private var selectedSide: Int = 1  // 0=左, 1=右
    @State private var showSettings: Bool = true

    private let sideLabels = ["左手 (Left)", "右手 (Right)"]
    private let sideValues: [UInt8] = [0, 1]

    var body: some View {
        ZStack {
            // AR 相机预览背景
            ARViewContainer(arSession: streamer.arSession)
                .ignoresSafeArea()

            // 前景 UI
            VStack {
                // 顶部状态栏
                statusBar

                Spacer()

                // 底部控制面板
                controlPanel
            }
            .padding()
        }
    }

    // MARK: - 状态栏

    var statusBar: some View {
        HStack {
            Circle()
                .fill(streamer.isStreaming ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            Text(streamer.statusText)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()
            if streamer.isStreaming {
                Text("\(streamer.fps) Hz")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
            }
        }
        .padding(10)
        .background(.black.opacity(0.6))
        .cornerRadius(10)
    }

    // MARK: - 控制面板

    var controlPanel: some View {
        VStack(spacing: 12) {
            // 展开/收起设置
            if showSettings {
                settingsSection
            }

            // 手的左右选择
            Picker("手", selection: $selectedSide) {
                ForEach(0..<sideLabels.count, id: \.self) { i in
                    Text(sideLabels[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .disabled(streamer.isStreaming)

            // 启动/停止按钮
            HStack(spacing: 16) {
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(.gray.opacity(0.7))
                        .cornerRadius(10)
                }

                Button(action: toggleStreaming) {
                    Label(
                        streamer.isStreaming ? "停止推流" : "开始推流",
                        systemImage: streamer.isStreaming ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(streamer.isStreaming ? Color.red.opacity(0.8) : Color.blue.opacity(0.8))
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(.black.opacity(0.65))
        .cornerRadius(16)
    }

    // MARK: - 设置面板

    var settingsSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("📡 电脑 IP 地址")
                    .foregroundColor(.gray)
                    .font(.caption)
                Spacer()
            }
            TextField("192.168.1.100", text: $ipAddress)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .disabled(streamer.isStreaming)

            HStack {
                Text("🔌 UDP 端口")
                    .foregroundColor(.gray)
                    .font(.caption)
                Spacer()
                Text("左手: 9998  右手: 9999")
                    .foregroundColor(.gray)
                    .font(.caption2)
            }
            TextField("9999", text: $portStr)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .disabled(streamer.isStreaming)

            Text("💡 提示：两台 iPhone 使用不同端口，左手用 9998，右手用 9999")
                .font(.caption2)
                .foregroundColor(.orange)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - 动作

    func toggleStreaming() {
        if streamer.isStreaming {
            streamer.stop()
        } else {
            let port = UInt16(portStr) ?? 9999
            streamer.start(ip: ipAddress, port: port, side: sideValues[selectedSide])
        }
    }
}

// MARK: - AR 相机视图桥接

struct ARViewContainer: UIViewRepresentable {
    let arSession: ARSession

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session = arSession
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

#Preview {
    ContentView()
}
