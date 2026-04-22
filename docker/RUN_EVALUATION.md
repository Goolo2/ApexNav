# 跑一次完整评测（容器内操作手册）

> 前置：镜像 `apexnav:jazzy` 已构建完成、`data/` 下模型权重和 HM3D/MP3D 数据集已就位。
> 镜像构建与宿主准备见 [README.md](./README.md)。

本文档只覆盖日常使用路径：**启动容器 → colcon build → 起 VLM 服务 → 起 RViz → 起 habitat_evaluation → 起 exploration_manager → 查结果**。

> **两个关键认知**（踩过的坑）：
> 1. 容器默认进 shell **自动激活 conda base (py3.13)**，非目标环境。每个终端开头都要显式切到对应 Python（见下）。
> 2. `entrypoint.sh` 只在容器首次启动跑一次，**`docker exec` 新 shell 不继承** ROS 和 PYTHONPATH，每个终端都得手动 `source`。

| 用途 | 正确 Python | 注意事项 |
|---|---|---|
| `colcon build` | `/usr/bin/python3.12`（先 `conda deactivate`） | cmake/python 都要走系统 |
| 4 个 VLM 服务 | `conda activate apexnav` 下的 py3.9 | 带 `HTTPS_PROXY` 拉 HuggingFace 权重 |
| `habitat_evaluation.py` | `/usr/bin/python3.12`（先 `conda deactivate`） | 必须 `export PYTHONPATH=/opt/GroundingDINO:/workspace/ApexNav:$PYTHONPATH` |
| `ros2 launch exploration_manager ...` | `/usr/bin/python3.12` | 同上 deactivate；只需 source ROS，不需 PYTHONPATH |

---

## 1. 启动/进入容器

宿主执行：
```bash
cd /home/viggo/projects/ApexNav
bash docker/docker-run.sh
```

`docker-run.sh` 会做：
- 容器**不存在**时 `docker run` 新建（`--gpus all --net=host --ipc=host --privileged`，挂载仓库到 `/workspace/ApexNav`、挂载 `data/torch_cache/hub` 持久化 BLIP2 权重、转发 X11）
- 容器**已存在**时 `docker start` + `docker exec -it` 直接进入
- 设置 `ROS_DOMAIN_ID=42`，与宿主 ROS2 节点（Franka 等）隔离

后续开多个终端时，在宿主再跑一次 `bash docker/docker-run.sh` 即可复用同一容器进入新 shell。

---

## 2. 首次 colcon build（只做一次）

容器 **`~/.bashrc` 会自动激活 conda base (py3.13)**，这会污染 `python3` / `cmake`。
colcon build 前先退出 conda：

```bash
conda deactivate            # 回到系统 PATH；python3 → /usr/bin/python3.12
cd /workspace/ApexNav
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

**关键**：build 必须用系统 `python3.12`。没 `conda deactivate` 会看到 "No module named 'em'"
或 "CMake 3.20+ required"（conda base 带的 cmake 3.14 顶掉了系统 3.28）。

> **关于 entrypoint.sh**：`entrypoint.sh` 只在**容器启动时**跑一次（`docker run` 的首条命令），
> 创建 `yolov7/`、`GroundingDINO/` 软链并设 PYTHONPATH。之后 `docker exec` 开的新 shell **不会**
> 继承这些 `source` 过的变量 — 每个新终端都要手动重跑 `source /opt/ros/jazzy/setup.bash`
> 和 `source install/setup.bash`。`PYTHONPATH` 也同样需要手动带上（见终端 6）。

---

## 3. 跑一次评测需要的 7 个终端

推荐用 `tmux`。每个终端进容器后都在 `/workspace/ApexNav` 下。

### 终端 1-4：4 个 VLM 服务

VLM 依赖装在 conda 的 `apexnav` 环境（py3.9）。默认进 shell 是 conda **base** (py3.13) — 没这些包，必须显式切到 `apexnav`：

```bash
conda activate apexnav      # 每个 VLM 终端都要先切

# 终端 1 — GroundingDINO（首次要下 bert-base-uncased ~420 MB）
HTTPS_PROXY=http://127.0.0.1:7890 python3 -m vlm.detector.grounding_dino --port 12181

# 终端 2 — BLIP2 ITM（首次要下 eva_vit_g 1.9 GB + blip2_pretrained 713 MB）
HTTPS_PROXY=http://127.0.0.1:7890 python3 -m vlm.itm.blip2itm --port 12182

# 终端 3 — MobileSAM（直接读 data/mobile_sam.pt）
python3 -m vlm.segmentor.sam --port 12183

# 终端 4 — YOLOv7（直接读 data/yolov7-e6e.pt）
python3 -m vlm.detector.yolov7 --port 12184
```

说明：
- 权重落在 `/root/.cache/torch/hub` 和 `/root/.cache/huggingface`，前者已挂载到宿主 `data/torch_cache/hub`，BLIP2 大权重持久化。HuggingFace 的 `bert-base-uncased` 走的是默认缓存，不跨容器重建持久化 — 若容器被 rm 会重下。
- 4 个服务全部打印 `Running on http://localhost:12xxx` 才算 ready。热启动（权重已缓存）约 15-30 秒；冷启动首次下权重约 2-5 分钟。

### 终端 5：RViz2（可选但推荐）

> 宿主需要桌面 + 第一次启容器前跑过 `xhost +local:docker`（`docker-run.sh` 已自动做）。

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source install/setup.bash
export DISPLAY=:1              # docker exec 新 shell 不继承 DISPLAY，必须手动设
                               # 值取宿主的 echo $DISPLAY（通常 :0 或 :1）
ros2 launch exploration_manager rviz.launch.py
```

> **坑**：`docker exec` 进入的 shell 不继承 `docker run -e DISPLAY` 设的环境变量。
> 不设 `DISPLAY` 会报 `qt.qpa.xcb: could not connect to display` 然后 rviz2 崩溃。

会打开 RViz2 并加载 `ApexNav.rviz`，核心话题：
- `/grid_map/value_map` — **语义 value map**（彩色点云，核心可视化）
- `/grid_map/occupied` / `/grid_map/free` / `/grid_map/esdf` — 占据栅格 / ESDF
- `/grid_map/depth_cloud` — 深度点云
- `/detector/clouds_with_scores` — 检测到的物体点云
- `/habitat/odom` — agent 位姿
- `/kinoastar/FlatPath` — 规划路径

### 终端 6：habitat_evaluation（**先启**）

必须用系统 `python3.12`（只有它装了 rclpy）+ 显式加 `PYTHONPATH`（让它找得到 `groundingdino` 包，entrypoint 设过但 `docker exec` 新 shell 不继承）：

```bash
conda deactivate            # 避免 py3.13 抢占
source /opt/ros/jazzy/setup.bash
source install/setup.bash
export PYTHONPATH="/opt/GroundingDINO:/workspace/ApexNav:${PYTHONPATH}"

/usr/bin/python3.12 -u habitat_evaluation.py \
    --dataset hm3dv2 habitat.dataset.split=val_mini test_epi_num=0
```

启动后会先打印一串 habitat-sim 日志，然后**阻塞在 `Waiting for ROS to get odometry...`**（每秒刷一行）。
这是**正常的** — 脚本在等 exploration_manager 回发 action 才会推进到 `Agent is ready to go!!!!`。
**不要**等这条消息再去起终端 7，否则会死锁。看到 "Waiting for ROS to get odometry" 就直接去起 exploration_manager。

漏掉 `PYTHONPATH` 的症状：
```
ModuleNotFoundError: No module named 'groundingdino'
```

### 终端 7：exploration_manager（**后启**）

```bash
conda deactivate            # 同上
source /opt/ros/jazzy/setup.bash
source install/setup.bash
ros2 launch exploration_manager exploration.launch.py
```

> **启动顺序必须先 habitat_evaluation 再 exploration_manager**。
> `/habitat/plan_action` 的 QoS 为 VOLATILE durability，exploration 先起的话第一条 action 会丢，订阅端永远收不到 → 死锁。

起来后终端 6 的 "Waiting for ROS to get odometry" 循环会停下，接着打印 `Agent is ready to go!!!!` 和每步的 `--------------Step: N--------------`。

---

## 4. 查看结果

habitat_evaluation 在 1-5 分钟内跑完一个 episode（本机 RTX 5090 实测 episode 0 约 115 步 / 1 分钟），终端 6 会打印：
```
+--------------------------+---------+
|          Metric          | Average |
+--------------------------+---------+
|     Average Success      | 100.00% |
|       Average SPL        |  44.73% |
|     Average Soft SPL     |  43.49% |
| Average Distance to Goal |  0.1505 |
+--------------------------+---------+
Episode 1 data written to videos/test_hm3dv2_val_mini/record.txt
Result: success
```

`test_epi_num=0` 只跑一集；省略会跑完整个 split（HM3D-v2 val_mini 30 集）。跑完后 habitat_evaluation **不会自动退出**，它会继续进下一集并重新 block 在 "Waiting for ROS to get odometry"，这时要么 Ctrl+C 结束，要么重启 exploration_manager。

### 录视频

```bash
/usr/bin/python3.12 -u habitat_evaluation.py --dataset hm3dv2 habitat.dataset.split=val_mini test_epi_num=0 need_video=true
```

输出 `videos/video_once.mp4`（约 20 MB），三栏画面：

| 左 | 中 | 右 |
|---|---|---|
| **RGB 观测**（带 GroundingDINO 检测框） | **Depth 观测**（深度灰度图） | **Top-down map**（蓝=agent、灰=已探索、白=可通行、黑=障碍） |

> Value map **不在视频里**，它通过 ROS2 话题 `/grid_map/value_map` 实时发布，只能在 RViz 中看（终端 5）。

### 按需录 RViz（demo 分享用）

`need_video=true` 只录 RGB/Depth/Top-down 三栏，**不含 value map**。要录 RViz 画面（含 value map）就用宿主脚本：

宿主一次性装依赖：
```bash
sudo apt install ffmpeg xdotool
```

录制（宿主执行，不进容器）：
```bash
# 最常用：自动找 RViz 窗口开始录；Ctrl+C 停止
bash docker/record_rviz.sh

# 找不到窗口时手动点选
bash docker/record_rviz.sh --pick

# 录整个屏幕（多窗口同屏对比用）
bash docker/record_rviz.sh --full

# 其他参数
bash docker/record_rviz.sh --fps 60 --out videos/my_demo.mp4
```

输出默认落到 `docker/recordings/rviz_YYYYMMDD_HHMMSS.mp4`（H.264 + yuv420p，主流播放器直出）。
**不能**写到仓库 `videos/` — 那是容器里 root 创建的目录，宿主用户没写权限。`docker/recordings/` 已在 `.gitignore`。

时机：先把终端 5 RViz 开起来、话题订阅到位，再起录制；评测跑完 Ctrl+C 停。

限制与注意：
- 依赖宿主 X 显示，headless 机器不适用。
- 只录一个 RViz 窗口内可见区域，被其他窗口遮挡的部分会拍进去。
- RViz 上报的几何可能超出屏幕边界（高分屏 + 默认布局），脚本会自动 clamp 到屏幕内。
- `xdotool search --name 'RViz'` 会同时匹配 Qt 内部小窗口（3×3、1×1），脚本按"面积最大的一个"挑主窗。

---

## 5. Trajectory 模式（速度控制）

用于真实部署测试，MPC 替代离散动作。替换终端 5-7：

```bash
# 终端 5
ros2 launch exploration_manager rviz_traj.launch.py
# 终端 6
ros2 launch exploration_manager exploration_traj.launch.py
# 终端 7（conda deactivate + PYTHONPATH 同评测）
/usr/bin/python3.12 habitat_vel_control.py
```

在 RViz 中用 **"2D Goal Pose"** 手动触发探索。

---

## 6. 本流程相关故障

| 症状 | 解决 |
|---|---|
| `qt.qpa.xcb: could not connect to display` (RViz 崩溃) | `docker exec` 新 shell 不继承 DISPLAY。在容器内 `export DISPLAY=:1`（值取宿主 `echo $DISPLAY`） |
| `ModuleNotFoundError: No module named 'rclpy._rclpy_pybind11'` / `'rclpy'` | 用了 conda py3.9/3.13。改 `conda deactivate && /usr/bin/python3.12`，并先 `source /opt/ros/jazzy/setup.bash` |
| `ModuleNotFoundError: No module named 'groundingdino'`（跑 habitat_evaluation 时） | 漏了 `export PYTHONPATH="/opt/GroundingDINO:/workspace/ApexNav:$PYTHONPATH"`。`docker exec` 的新 shell 不继承 entrypoint.sh 设的 PYTHONPATH |
| `CMake Error: CMake 3.20 or higher is required` (colcon build 时) | PATH 中 conda cmake 在前。`conda deactivate` 或重开一个没激活 conda 的终端 |
| `Waiting for ROS to get odometry...` 卡住 | exploration_manager 还没起；或起反了顺序。两者都关掉，**先 habitat_eval，后 exploration** |
| `'Agent' object has no attribute 'sensors'` | habitat-lab 旧 API。Dockerfile 已 patch，老镜像需 sed 把 `agents[0].sensors` 改为 `agents[0]._sensors` |
| BLIP2 启动报 `failed finding central directory` | HuggingFace 下载被打断，缓存损坏。删 `/root/.cache/torch/hub/checkpoints/eva_vit_g.pth*` 重下 |
| 容器里收到非预期的 ROS 话题 | 宿主 ROS 节点经 `--net=host` 多播污染。确认 `ROS_DOMAIN_ID=42`（docker-run.sh 已设） |

其余构建期/镜像期坑见 [README.md §7](./README.md#7-常见故障)。
