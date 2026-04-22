# ApexNav 快速部署指南（使用预构建镜像）

你收到的文件：

| 文件 | 大小 | 说明 |
|---|---|---|
| `apexnav_jazzy.tar.gz` | ~15-20 GB | 预构建 Docker 镜像（含 ROS2、habitat-sim、PyTorch 等，无需自己编译） |
| `apexnav_data.tar.gz` | ~5 GB | 模型权重 + HuggingFace/torch 缓存 + HM3D/MP3D 数据集 |
| ApexNav 代码仓库 | ~100 MB | git clone 或 zip |

---

## 1. 宿主环境要求

- Ubuntu 22.04 / 24.04（桌面版，需要 X11 显示 RViz）
- NVIDIA 显卡 + 驱动 >= 555（RTX 5090 需 >= 570）
- 磁盘剩余空间 >= 60 GB

---

## 2. 安装 Docker + NVIDIA Container Toolkit（一次性）

### 2.1 安装 Docker

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# 退出终端重新登录，或执行 newgrp docker
```

### 2.2 安装 NVIDIA Container Toolkit

```bash
bash docker/install_nvidia_container_toolkit.sh
```

### 2.3 验证 GPU 透传

```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi -L
# 应输出: GPU 0: NVIDIA GeForce RTX xxxx (UUID: ...)
```

如果拉不动 nvidia/cuda 镜像（国内网络），先配镜像加速：
```bash
bash docker/configure_mirror.sh
```

---

## 3. 部署

### 3.1 放置代码

```bash
cd ~/projects                      # 或你喜欢的目录
git clone git@github.com:Goolo2/ApexNav.git        # 或解压 zip
cd ApexNav
git switch ros2-jazzy
```

### 3.2 加载 Docker 镜像

```bash
docker load < apexnav_jazzy.tar.gz
# 耗时几分钟，完成后 docker images 能看到 apexnav:jazzy
```

### 3.3 解压数据和权重

把 `apexnav_data.tar.gz` 放到 `ApexNav/` 目录下：
```bash
tar xzf apexnav_data.tar.gz
# 会解压出 data/ 目录，包含模型权重、缓存和数据集
```

解压后目录结构应该是：
```
ApexNav/
├── data/
│   ├── mobile_sam.pt                    # MobileSAM 权重
│   ├── yolov7-e6e.pt                    # YOLOv7 权重
│   ├── groundingdino_swint_ogc.pth      # GroundingDINO 权重
│   ├── torch_cache/hub/                 # BLIP2 权重缓存
│   ├── hf_cache/                        # HuggingFace 权重缓存
│   ├── datasets/objectnav/              # HM3D + MP3D 任务集
│   └── scene_datasets/                  # HM3D 3D 场景
├── docker/
├── src/
└── ...
```

### 3.4 HM3D 场景数据（如未包含）

如果 `data/scene_datasets/` 下为空或只有软链接，需要自行下载 HM3D minival 场景（需申请 Matterport token，https://matterport.com/partners/facebook ，约 10 分钟审批）：

```bash
bash docker/docker-run.sh   # 进容器
# 容器内：
python3 -m habitat_sim.utils.datasets_download \
    --username <你的token> --password <你的token> \
    --data-path data/scene_datasets \
    hm3d_minival
ln -sfn versioned_data/hm3d-0.2/hm3d data/scene_datasets/hm3d_v0.2
```

---

## 4. 跑一次评测

需要 **7 个终端**（推荐用 tmux）。每个终端都通过同一个命令进入容器：

```bash
cd ~/projects/ApexNav
bash docker/docker-run.sh
```

第一次会创建容器，后续再跑会自动进入已有容器。

### 终端 1：colcon build（首次进容器做一次）

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
colcon build
source install/setup.bash
```

> 必须先 `conda deactivate`，否则 conda 的 cmake 3.14 会顶掉系统 3.28 导致报错。

### 终端 2-5：4 个 VLM 服务

每个终端先切换 conda 环境，然后分别启动一个服务：

```bash
conda activate apexnav

# 终端 2 — GroundingDINO
python3 -m vlm.detector.grounding_dino --port 12181

# 终端 3 — BLIP2
python3 -m vlm.itm.blip2itm --port 12182

# 终端 4 — MobileSAM
python3 -m vlm.segmentor.sam --port 12183

# 终端 5 — YOLOv7
python3 -m vlm.detector.yolov7 --port 12184
```

> 如果下载 HuggingFace 权重报错/超时，加代理：`HTTPS_PROXY=http://127.0.0.1:7890 python3 -m ...`
> 权重已包含在 data 包中，正常情况 15-30 秒即可启动。
> 4 个服务都打印 `Running on http://localhost:12xxx` 才算就绪。

### 终端 6：RViz2（可选但推荐）

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source install/setup.bash
export DISPLAY=:1       # 值取宿主的 echo $DISPLAY（通常 :0 或 :1）
ros2 launch exploration_manager rviz.launch.py
```

### 终端 7：habitat_evaluation（先启）

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source install/setup.bash
export PYTHONPATH="/opt/GroundingDINO:/workspace/ApexNav:${PYTHONPATH}"

/usr/bin/python3.12 -u habitat_evaluation.py \
    --dataset hm3dv2 habitat.dataset.split=val_mini test_epi_num=0
```

启动后会打印 `Waiting for ROS to get odometry...`，这是正常的，直接去起终端 8。

### 终端 8：exploration_manager（后启）

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source install/setup.bash
ros2 launch exploration_manager exploration.launch.py
```

> **启动顺序很重要**：必须先 habitat_evaluation，后 exploration_manager。反过来会死锁。

启动后终端 7 会打印 `Agent is ready to go!!!!`，开始逐步评测。

---

## 5. 查看结果

评测完成后终端 7 会打印：
```
+--------------------------+---------+
|          Metric          | Average |
+--------------------------+---------+
|     Average Success      | 100.00% |
|       Average SPL        |  44.73% |
|     Average Soft SPL     |  43.49% |
| Average Distance to Goal |  0.1505 |
+--------------------------+---------+
```

- `test_epi_num=0` 只跑 1 集（约 1-5 分钟）
- 去掉 `test_epi_num=0` 会跑完整个 split（HM3D-v2 val_mini 共 30 集）
- 加 `need_video=true` 可录制 RGB/Depth/Top-down 三栏视频到 `videos/video_once.mp4`

---

## 6. 常见问题

| 症状 | 解决 |
|---|---|
| `No module named 'rclpy'` | 用了 conda 环境跑 ROS 节点。先 `conda deactivate`，用系统 `/usr/bin/python3.12` |
| `CMake 3.20 or higher is required` | 同上，`conda deactivate` 后重试 `colcon build` |
| `qt.qpa.xcb: could not connect to display` | 容器内没设 DISPLAY。`export DISPLAY=:1`（值取宿主 `echo $DISPLAY`） |
| `No module named 'groundingdino'` | 漏了 `export PYTHONPATH="/opt/GroundingDINO:/workspace/ApexNav:$PYTHONPATH"` |
| `Waiting for ROS to get odometry...` 一直卡住 | exploration_manager 没起，或启动顺序反了。两个都关掉，先 habitat_eval 后 exploration |
| BLIP2 报 `failed finding central directory` | 权重文件损坏。删 `/root/.cache/torch/hub/checkpoints/eva_vit_g.pth*` 重新下载 |
| VLM 服务下载权重超时 | 加代理 `HTTPS_PROXY=http://127.0.0.1:7890`，或确认 `data/hf_cache/` 和 `data/torch_cache/` 已正确解压 |

更多构建期问题见 [README.md](./README.md)，更多运行期细节见 [RUN_EVALUATION.md](./RUN_EVALUATION.md)。
