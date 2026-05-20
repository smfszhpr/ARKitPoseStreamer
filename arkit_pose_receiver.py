"""
arkit_pose_receiver.py — 接收两台 iPhone ARKit 姿态的 Python 端接收器

UDP 数据包格式 (37 bytes):
  [0-3]   magic "ARKT"
  [4]     side: 0=左手, 1=右手
  [5-8]   seq: UInt32 LE
  [9-36]  7 × Float32: tx, ty, tz, qx, qy, qz, qw

使用方式:
    receiver = ARKitPoseReceiver(left_port=9998, right_port=9999)
    receiver.start()
    while True:
        left = receiver.get_pose("left")
        right = receiver.get_pose("right")
        if left:
            print(f"Left wrist pos: {left['pos']}, quat: {left['quat']}")
"""

import socket
import struct
import threading
import time
import numpy as np
from typing import Optional


# UDP 包格式常量
MAGIC = b"ARKT"
PACKET_SIZE = 37  # 4+1+4+4*7
HEADER_FMT = "4sBi"   # magic(4s), side(B), seq(i)
FLOAT_FMT = "7f"       # tx,ty,tz,qx,qy,qz,qw
SIDE_NAMES = {0: "left", 1: "right"}


class ARKitPoseReceiver:
    """
    监听两个 UDP 端口，接收左右两台 iPhone 发来的 ARKit 6DOF 位姿。

    线程安全：内部用锁保护最新帧，可从主线程安全读取。
    """

    def __init__(self, left_port: int = 9998, right_port: int = 9999,
                 timeout: float = 0.01):
        self._ports = {"left": left_port, "right": right_port}
        self._timeout = timeout

        self._sockets: dict[str, socket.socket] = {}
        self._latest: dict[str, Optional[dict]] = {"left": None, "right": None}
        self._locks: dict[str, threading.Lock] = {
            "left": threading.Lock(),
            "right": threading.Lock()
        }
        self._threads: dict[str, threading.Thread] = {}
        self._running = False

        # 坐标对齐矩阵（需要 ArUco 标定后设置）
        # 变换格式: 4×4 float64, cam2 → cam1 世界坐标系
        self._align_matrix: Optional[np.ndarray] = None

    def start(self):
        """启动后台接收线程（每个手一个）。"""
        self._running = True
        for side, port in self._ports.items():
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("0.0.0.0", port))
            sock.settimeout(self._timeout)
            self._sockets[side] = sock

            t = threading.Thread(target=self._recv_loop, args=(side,), daemon=True)
            t.start()
            self._threads[side] = t
            print(f"[ARKitReceiver] Listening for {side} hand on port {port}")

    def stop(self):
        """停止接收。"""
        self._running = False
        for sock in self._sockets.values():
            try:
                sock.close()
            except Exception:
                pass

    def get_pose(self, side: str) -> Optional[dict]:
        """
        获取最新的手腕位姿。

        Returns:
            {
              "pos":  np.ndarray shape (3,) float32,  # [x, y, z] 米
              "quat": np.ndarray shape (4,) float32,  # [qx, qy, qz, qw]
              "seq":  int,                             # 包序号
              "side": str,                             # "left" or "right"
              "timestamp": float                       # 本地接收时间 (time.time())
            }
            或 None（尚未收到数据）
        """
        with self._locks[side]:
            return self._latest[side]

    def get_pose_matrix(self, side: str) -> Optional[np.ndarray]:
        """
        返回手腕位姿的 4×4 变换矩阵（相机坐标系下）。

        如果设置了坐标对齐矩阵（set_alignment_matrix），
        会自动将右手坐标系转换到左手坐标系。
        """
        pose = self.get_pose(side)
        if pose is None:
            return None

        pos = pose["pos"]
        q = pose["quat"]  # [qx, qy, qz, qw]

        # 四元数 → 旋转矩阵 (用 scipy 或手算)
        try:
            from scipy.spatial.transform import Rotation
            rot = Rotation.from_quat(q).as_matrix()  # (3,3)
        except ImportError:
            rot = _quat_to_mat(q)

        T = np.eye(4, dtype=np.float64)
        T[:3, :3] = rot
        T[:3, 3] = pos

        # 如果有对齐矩阵，变换到统一坐标系
        if self._align_matrix is not None and side == "right":
            T = self._align_matrix @ T

        return T

    def set_alignment_matrix(self, T: np.ndarray):
        """
        设置坐标对齐矩阵：将右手 iPhone 坐标系转换到左手 iPhone 坐标系。

        T: 4×4 float64，通过 ArUco 标定求得的 T_right_to_left
        """
        assert T.shape == (4, 4), "对齐矩阵必须是 4×4"
        self._align_matrix = T.astype(np.float64)
        print(f"[ARKitReceiver] 坐标对齐矩阵已设置")

    # MARK: - 内部

    def _recv_loop(self, side: str):
        sock = self._sockets[side]
        while self._running:
            try:
                data, addr = sock.recvfrom(64)
                if len(data) < PACKET_SIZE:
                    continue

                # 解包 header
                magic = data[0:4]
                if magic != MAGIC:
                    continue

                recv_side_byte = data[4]
                seq = struct.unpack_from("<I", data, 5)[0]

                # 解包 7 个 floats
                floats = struct.unpack_from("<7f", data, 9)
                tx, ty, tz = floats[0], floats[1], floats[2]
                qx, qy, qz, qw = floats[3], floats[4], floats[5], floats[6]

                frame = {
                    "pos": np.array([tx, ty, tz], dtype=np.float32),
                    "quat": np.array([qx, qy, qz, qw], dtype=np.float32),
                    "seq": seq,
                    "side": side,
                    "timestamp": time.time(),
                }
                with self._locks[side]:
                    self._latest[side] = frame

            except socket.timeout:
                continue
            except Exception as e:
                if self._running:
                    print(f"[ARKitReceiver] {side} recv error: {e}")


def _quat_to_mat(q: np.ndarray) -> np.ndarray:
    """四元数 [qx, qy, qz, qw] → 3×3 旋转矩阵（不依赖 scipy）。"""
    qx, qy, qz, qw = q
    return np.array([
        [1 - 2*(qy*qy + qz*qz), 2*(qx*qy - qz*qw), 2*(qx*qz + qy*qw)],
        [2*(qx*qy + qz*qw), 1 - 2*(qx*qx + qz*qz), 2*(qy*qz - qx*qw)],
        [2*(qx*qz - qy*qw), 2*(qy*qz + qx*qw), 1 - 2*(qx*qx + qy*qy)],
    ], dtype=np.float64)


# ── 简单测试 ──────────────────────────────────────────────────────────────
if __name__ == "__main__":
    receiver = ARKitPoseReceiver(left_port=9998, right_port=9999)
    receiver.start()

    print("等待 iPhone 发送数据（确保手机和电脑在同一 Wi-Fi 下）...")
    print("按 Ctrl+C 退出\n")

    try:
        while True:
            for side in ["left", "right"]:
                pose = receiver.get_pose(side)
                if pose:
                    pos = pose["pos"]
                    q = pose["quat"]
                    print(f"[{side.upper():5s}] pos=({pos[0]:+.3f}, {pos[1]:+.3f}, {pos[2]:+.3f})m  "
                          f"quat=({q[0]:+.3f},{q[1]:+.3f},{q[2]:+.3f},{q[3]:+.3f})  seq={pose['seq']}")
            time.sleep(0.1)
    except KeyboardInterrupt:
        receiver.stop()
        print("退出")
