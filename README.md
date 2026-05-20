# ARKitPoseStreamer — iOS 手腕位姿无线追踪 App

**给帮忙编译的人看** | 给使用者看

---

## 项目说明

这是一个 iOS ARKit App，将 iPhone 的 6DOF 空间位姿（位置+朝向）通过 **Wi-Fi UDP** 实时发送到电脑。  
配合 Manus 手套使用，让电脑知道"手在哪个位置"（Manus 只知道手指弯了多少，不知道手在空间中的位置）。

---

## 给帮忙编译的人

### 需要什么

- macOS 13+
- Xcode 15+（App Store 免费下载）
- 一个 Apple Developer 账号（个人免费账号即可，用于真机调试）
- USB 数据线（仅用于第一次安装 App 到 iPhone，安装后可以拔掉）

### 步骤

#### 1. 创建 Xcode 项目

1. 打开 Xcode → `File → New → Project`
2. 选择 `iOS → App`，点 `Next`
3. 填写:
   - **Product Name**: `ARKitPoseStreamer`
   - **Team**: 选你的 Apple 账号（如没有，在 Xcode Preferences → Accounts 中添加）
   - **Bundle Identifier**: `com.yourname.ARKitPoseStreamer`（随意，只要唯一）
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
4. 选一个位置保存，点 `Create`

#### 2. 替换源文件

把 Xcode 项目里**默认生成的文件全部删掉**（删除时选"Move to Trash"），然后：

1. 把这个目录 `ARKitPoseStreamer/` 里的三个 `.swift` 文件拖进 Xcode 的项目导航（左侧文件树）：
   - `ARKitPoseStreamerApp.swift`
   - `ContentView.swift`
   - `PoseStreamer.swift`

2. **添加 Info.plist 权限**（重要！不然相机/网络会被拒绝）：
   - 在 Xcode 左侧点选项目名 → 选 `TARGETS → ARKitPoseStreamer → Info`
   - 在 `Custom iOS Target Properties` 里添加以下两项（点 `+` 按钮）：
   
   | Key | Type | Value |
   |-----|------|-------|
   | `Privacy - Camera Usage Description` | String | `ARKitPoseStreamer 需要相机权限来运行 ARKit 追踪手部空间位置。` |
   | `Privacy - Local Network Usage Description` | String | `ARKitPoseStreamer 需要局域网访问权限来将手部位姿数据通过 UDP 发送到电脑。` |

   或者，直接把 `Info.plist` 文件也拖入项目，然后在项目 Build Settings 里把 `Info.plist File` 指向它。

#### 3. 添加 RealityKit 框架

1. 点选项目名 → `TARGETS → ARKitPoseStreamer → General → Frameworks, Libraries...`
2. 点 `+` → 搜索 `RealityKit` → 添加

#### 4. 编译并安装到 iPhone

1. 用 USB 线连接 iPhone 到 Mac
2. iPhone 上信任这台电脑（弹窗选"信任"）
3. 在 Xcode 顶部选择你的 iPhone 为目标设备
4. 点击 `▶ Run`（或 Cmd+R）
5. 首次运行会提示在 iPhone 设置里信任开发者证书：  
   `设置 → 通用 → VPN与设备管理 → 开发者 App → 信任`
6. App 安装完成，USB 可以拔掉了，App 已保存在手机上

---

## 给使用者（运行 App 人）

### App 使用方法

1. **手机和电脑连接同一个 Wi-Fi**（或手机开热点，电脑连手机热点）

2. **查看电脑 IP**（Python 端监听的地址）：
   ```bash
   ip addr show | grep "inet " | grep -v 127.0.0.1
   # 输出类似: inet 192.168.1.105/24
   # 那 IP 就是 192.168.1.105
   ```

3. **配置 App**：
   - 打开 App，点齿轮图标展开设置
   - 输入电脑的 IP 地址（如 `192.168.1.105`）
   - **左手 iPhone 端口填 `9998`，右手 iPhone 端口填 `9999`**
   - 选择对应手（左手/右手）
   - 点"开始推流"

4. **两台 iPhone 都这样设置**，端口不同（9998/9999）

5. **验证**：在 PC 上运行测试脚本：
   ```bash
   python arkit_pose_receiver.py
   ```
   应该能看到实时打印的位置和四元数。

### 手机固定到手套上

- 把 iPhone 固定到手套的手背侧（不遮挡手指）
- 推荐用手机支架 + 魔术贴固定到手腕/手背部分
- 镜头朝上或朝前，ARKit 需要看到有纹理的环境（别对着白墙）
- 固定后不要再移动手机相对手套的位置（不然标定失效）

### ARKit 注意事项

- 光线要充足，ARKit 靠视觉特征追踪
- 第一次启动让 ARKit 初始化 2-3 秒（慢慢移动手机环视一下环境）
- 避免极快速甩动（> 2m/s）
- 长时间使用会有轻微漂移，重新打开 App 可以重置

---

## PC 端 Python 接收器

```bash
python arkit_pose_receiver.py
# 或在代码里导入:
from arkit_pose_receiver import ARKitPoseReceiver
```

### 集成到 dex2bench 的示意（非完整代码，仅展示结构）

```python
from arkit_pose_receiver import ARKitPoseReceiver

# 初始化
pose_receiver = ARKitPoseReceiver(left_port=9998, right_port=9999)
pose_receiver.start()

# 在仿真循环里:
right_wrist = pose_receiver.get_pose("right")
if right_wrist is not None:
    wrist_pos = right_wrist["pos"]   # [x, y, z] 米
    wrist_quat = right_wrist["quat"] # [qx, qy, qz, qw]
    # → 送给机械臂 IK 控制器
```

---

## 文件说明

```
ARKitPoseStreamer/
├── ARKitPoseStreamer/
│   ├── ARKitPoseStreamerApp.swift   # 入口
│   ├── ContentView.swift            # 主界面（SwiftUI）
│   ├── PoseStreamer.swift           # 核心：ARKit + UDP 发送
│   └── Info.plist                   # 权限声明
├── arkit_pose_receiver.py          # PC 端 Python 接收器
└── README.md                        # 本文件
```

---

## 常见问题

| 问题 | 解决方法 |
|------|---------|
| Python 收不到数据 | 检查防火墙是否放行 UDP 9998/9999 端口：`sudo ufw allow 9998/udp && sudo ufw allow 9999/udp` |
| App 闪退 | 检查是否添加了相机权限的 Info.plist 条目 |
| ARKit 追踪失败（红屏） | 光线不足，或移动太快，重启 App |
| 两台 iPhone 位置不对齐 | 需要 ArUco 标记板标定（见 wireless_hand_tracking_analysis.md）|
| 编译报错 "RealityKit not found" | 回到 Xcode Frameworks 添加 RealityKit |
| 编译报错 `Build input file cannot be found: ...-Bridging-Header.h` | **Xcode 项目设置里有一个多余的 Bridging Header 路径，需要清除**：<br>1. 点选左侧项目名 → `TARGETS → ARKitPoseStreamer → Build Settings`<br>2. 搜索 `Bridging Header`<br>3. 找到 `Objective-C Bridging Header`，**双击值，全选删除，按 Delete，按 Enter 确认**（把路径清空）<br>4. 重新 Build |
