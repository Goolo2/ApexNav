# ApexNav Docker

从零跑通 ApexNav (ROS2 Jazzy port) 的 Docker 环境。
基础镜像 `nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04`，系统 **Python 3.12**，
自编 habitat-sim，4 个 VLM 服务 + exploration_manager 规划节点。

---

## 0. 目录内容

```
docker/
├── Dockerfile                          # 镜像构建脚本（重头戏）
├── entrypoint.sh                       # 容器启动时：source ROS、link 外部仓库
├── docker-run.sh                       # 启动容器（GPU / X11 / 挂载）
├── configure_mirror.sh                 # 宿主一次性配置 Docker registry 镜像
├── install_nvidia_container_toolkit.sh # 宿主一次性装 nvidia-container-toolkit
├── README.md                           # 本文件
└── .secrets/                           # gitignored
    └── download_hm3d_minival.sh        # 用你的 HM3D token 下 minival 场景
```

---

## 1. 宿主准备（一次性，需要 sudo）

### 1.1 必备
- Ubuntu 22.04/24.04
- NVIDIA 驱动 ≥ 555（支持 CUDA 12.8 runtime；实测 RTX 5090 需要驱动 ≥ 570，但 NVIDIA 515+ 也能装 toolkit）
- GPU 架构需 **sm_120 (Blackwell/5090)** 或旧的 sm_80/86/89（Ampere/Ada）都可，只要 CUDA 12.8 支持

### 1.2 装 Docker
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# 退出重新登录，或 `newgrp docker`
```

### 1.3 装 nvidia-container-toolkit
```bash
bash docker/install_nvidia_container_toolkit.sh
```

**坑**：`nvidia.github.io` 的 GPG key 早期写法要用 `gpg --dearmor` 但有时文件会变成空。
脚本里加了 `test -s` 做健全性检查，空的会报错退出。

### 1.4 Docker registry 镜像加速（国内必做）
```bash
bash docker/configure_mirror.sh
```
把 `docker.1ms.run`、`docker.m.daocloud.io`、`docker.1panel.live` 等写进 `/etc/docker/daemon.json`，
保留已有的 `runtimes.nvidia` 配置。基础镜像 5.8 GB，没这步要下 1+ 小时。

### 1.5 验证 GPU 能透传
```bash
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi -L
# 应输出: GPU 0: NVIDIA GeForce RTX 5090 (UUID: ...)
```

---

## 2. 构建镜像

### 2.1 数据 & 权重（宿主）
模型权重 3 个（挂载到容器内 `data/`）：
```bash
cd /home/viggo/projects/ApexNav  # 或你的仓库路径
mkdir -p data
wget -O data/mobile_sam.pt \
    https://github.com/ChaoningZhang/MobileSAM/raw/master/weights/mobile_sam.pt
wget -O data/groundingdino_swint_ogc.pth \
    https://github.com/IDEA-Research/GroundingDINO/releases/download/v0.1.0-alpha/groundingdino_swint_ogc.pth
wget -O data/yolov7-e6e.pt \
    https://github.com/WongKinYiu/yolov7/releases/download/v0.1/yolov7-e6e.pt
```

HM3D v2 ObjectNav 任务集：
```bash
mkdir -p data/datasets/objectnav/hm3d
wget -O data/datasets/objectnav/hm3d/v2.zip \
    https://dl.fbaipublicfiles.com/habitat/data/datasets/objectnav/hm3d/v2/objectnav_hm3d_v2.zip
unzip data/datasets/objectnav/hm3d/v2.zip -d data/datasets/objectnav/hm3d
mv data/datasets/objectnav/hm3d/objectnav_hm3d_v2 data/datasets/objectnav/hm3d/v2
rm data/datasets/objectnav/hm3d/v2.zip
```

MP3D ObjectNav（habitat_evaluation.py 硬编码读取 `mp3d/v1/val/val.json.gz` 取类别名映射；必须有）：
```bash
mkdir -p data/datasets/objectnav/mp3d
wget -O data/datasets/objectnav/mp3d/v1.zip \
    https://dl.fbaipublicfiles.com/habitat/data/datasets/objectnav/m3d/v1/objectnav_mp3d_v1.zip
unzip data/datasets/objectnav/mp3d/v1.zip -d data/datasets/objectnav/mp3d/v1
rm data/datasets/objectnav/mp3d/v1.zip
```

### 2.2 构建命令

**推荐（带 VPN 代理）**：
```bash
docker build \
    --network=host \
    --build-arg PIP_PROXY=http://127.0.0.1:7890 \
    -f docker/Dockerfile \
    -t apexnav:jazzy .
```
- `--network=host` 让容器内构建时能访问宿主 127.0.0.1 的代理端口
- `PIP_PROXY` 是自定义 build-arg，Dockerfile 对关键 pip 步骤走代理
- 无代理时可省略 `--build-arg`，但 `pypi.nvidia.com` 等域慢到爬

**完整构建约 60-90 分钟**，镜像 ~14 GB。

### 2.3 构建流程 & 踩坑记录

按 Dockerfile 顺序：

| 步骤 | 耗时 | 坑 / 解决 |
|---|---|---|
| 1. apt 镜像 (aliyun) | 秒级 | Ubuntu 24.04 用 deb822 格式，同时改 `sources.list` 和 `ubuntu.sources` |
| 2. 系统依赖 | ~5 min | 包含 habitat-sim 编译所需 `libjpeg-dev/libglm-dev/libegl1-mesa-dev/xorg-dev/freeglut3-dev` |
| 3. ROS2 Jazzy | ~20 min | 走清华镜像。`ros-jazzy-desktop` 拖 1100+ 包 / 735 MB |
| 4. pip 镜像 (aliyun) | 秒级 | - |
| 5. **PyTorch 2.9.1+cu128** | ~10-15 min | **关键**：必须 cu128 匹配基础镜像 CUDA 12.8。原本试 2.11+cu130 会让 GroundingDINO 编译失败（CUDA 版本不匹配） |
| 6. Python 依赖 | ~10 min | **一堆坑**：<br>• `numpy==1.26.4` pin（habitat-sim / cv2 要 1.x，否则 `numpy._core.multiarray failed to import`）<br>• `transformers==4.40.2`（lavis 1.0.2 要 `apply_chunking_to_forward`，新版移除；太旧又需 Rust 编 tokenizers）<br>• `salesforce-lavis --no-deps` + 手列依赖（否则 pip 解析 spacy 3.8.13 要 `thinc>=8.3.12` 但 aliyun 镜像和 py3.12 都没有此版本）<br>• `--ignore-installed numpy blinker`（debian 装的 python3-numpy / python3-blinker 没 RECORD 文件，pip 卸不掉） |
| 7. yolov7 + GroundingDINO | ~5 min | yolov7 的 `torch.load` 要改成 `weights_only=False`（torch 2.6+ 默认 True）<br>GroundingDINO wheel build 可能失败（CUDA 扩展），但 Python 源码 import 能用，仅报 "Failed to load custom C++ ops. Running on CPU mode Only"（对我们足够） |
| 8. habitat-lab (main) | ~5 min | **不能用 v0.3.1**：v0.3.1 的 `default_structured_configs.py` 对 py3.12 的 dataclass 新限制不兼容。main 分支已修复<br>装完要**补打 nav.py 补丁**：`Agent.sensors → Agent._sensors`（habitat-sim 0.3.3 改名） |
| 9. **habitat-sim 源码编译** | ~30-60 min | **最耗时**。`python setup.py install --bullet --with-cuda`<br>**坑**：setup.py 最后执行 `pip install build/deps/magnum-bindings/src/python` 但没带 `--break-system-packages`，py3.12 PEP 668 拒绝，会报错。我在 Dockerfile 里显式跑这句并设 `PIP_BREAK_SYSTEM_PACKAGES=1` |
| 10. OsqpEigen | ~1 min | colcon build `trajectory_manager` 需要；apt 无包，源码编。`-Dosqp_DIR=/opt/ros/jazzy/lib/cmake/osqp`（`ros-jazzy-osqp-vendor` 提供） |

### 2.4 通用 CN 环境的几个镜像
- **apt**: `mirrors.aliyun.com/ubuntu`
- **ROS2**: `mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu`
- **pip**: `mirrors.aliyun.com/pypi/simple`（默认），不在里面的包走 pypi.org via 代理
- **pytorch**: `mirrors.tuna.tsinghua.edu.cn/pytorch-wheels/cu128/`（无代理时），或 `download.pytorch.org/whl/cu128`（有代理时）
- **conda**（已不用）: `mirrors.tuna.tsinghua.edu.cn/anaconda/*`
- **Miniconda 安装器**: `mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/`

---

## 3. 场景数据集（HM3D minival）

HM3D 场景需 Matterport token（申请地址 https://matterport.com/partners/facebook，10 分钟审批）。
把 token 填进 `docker/.secrets/download_hm3d_minival.sh`（gitignored），容器内跑：

```bash
bash docker/docker-run.sh   # 进容器
# 容器内：
bash docker/.secrets/download_hm3d_minival.sh   # ~240 MB
# 场景会落到 data/scene_datasets/versioned_data/hm3d-0.2/hm3d/minival/
# habitat 默认找 data/scene_datasets/hm3d_v0.2/；软链接一下：
ln -sfn versioned_data/hm3d-0.2/hm3d data/scene_datasets/hm3d_v0.2
```

---

## 4. 跑评测（进容器 → 出结果）

从这一步开始是日常使用路径，已单独拆到 **[RUN_EVALUATION.md](./RUN_EVALUATION.md)**，覆盖：
启动/进入容器 → 首次 `colcon build` → 起 4 个 VLM 服务 → RViz → habitat_evaluation → exploration_manager → 查结果 / 录视频 / Trajectory 模式。

简版速览：
```bash
# 宿主
bash docker/docker-run.sh

# 容器内首次
source /opt/ros/jazzy/setup.bash && colcon build && source install/setup.bash

# 7 个终端分别起：VLM×4 → RViz → habitat_evaluation（先）→ exploration_manager（后）
```

> **启动顺序的坑**：必须先 `habitat_evaluation`、后 `exploration_manager`。
> `/habitat/plan_action` QoS 为 VOLATILE，反过来会丢首条 action 死锁。

---

## 7. 常见故障

| 症状 | 原因 / 解决 |
|---|---|
| `ModuleNotFoundError: No module named 'rclpy._rclpy_pybind11'`（.so cpython-39 找不到） | 误用了 conda env 的 py3.9。**改用系统 `/usr/bin/python3`** |
| `CMake Error: CMake 3.20 or higher is required.  You are running version 3.14.0` | PATH 中 conda 的 cmake 3.14 在前。`export PATH=/opt/ros/jazzy/bin:/usr/bin:$PATH` 或直接不激活 conda |
| habitat_eval 一直 `Waiting for ROS to get odometry...` | exploration_manager 还没起；或 exploration 先启动把 action 发空了（重启两者，先 habitat_eval 后 exploration） |
| `Unexpected error occurred: 'Agent' object has no attribute 'sensors'` | habitat-lab 用旧 API。Dockerfile 已补丁；老镜像可手工 `sed` 改 `agents[0].sensors → agents[0]._sensors` |
| `RuntimeError: The detected CUDA version (12.8) mismatches the version that was used to compile PyTorch (13.0)` | torch 装成了 cu13 版。必须 `torch==2.9.1 --index-url .../cu128` |
| `externally-managed-environment` (PEP 668) | 设环境变量 `PIP_BREAK_SYSTEM_PACKAGES=1` 或加 `--break-system-packages` |
| BLIP2 启动时 `PytorchStreamReader failed reading zip archive: failed finding central directory` | HuggingFace 下载被中断，缓存损坏。删 `/root/.cache/torch/hub/checkpoints/eva_vit_g.pth*` 重新下载 |
| exploration 报 `OsqpEigenConfig.cmake not found` | 漏装 OsqpEigen。Dockerfile 已处理；手工补：`cmake .. -Dosqp_DIR=/opt/ros/jazzy/lib/cmake/osqp && make install` |
| 容器里 ROS 话题干扰 | 宿主 ROS2 节点（Franka 等）经 `--net=host` 多播污染。`ROS_DOMAIN_ID=42` 隔离（docker-run.sh 已设） |

---

## 8. 双 Python 架构说明

镜像里有两套 Python，各负其责：

| Python | 路径 | 用途 | 关键包 |
|---|---|---|---|
| **conda apexnav (py3.9)** | `conda activate apexnav` → `/opt/miniconda3/envs/apexnav/bin/python` | VLM 服务（grounding_dino / blip2 / sam / yolov7） | torch cu128, salesforce-lavis, mobile_sam, habitat-sim 0.3.1 (conda 预编译) |
| **system (py3.12)** | `/usr/bin/python3.12` | habitat_evaluation.py + rclpy + colcon build | torch 2.9.1 cu128, rclpy (ROS2), habitat-sim 0.3.3 (源码编译), habitat-lab (main) |

**为什么需要两套？**
- VLM 依赖 (salesforce-lavis, habitat-sim 0.3.1 conda 包) 只有 py3.9 版本
- rclpy (ROS2 Jazzy) 只有 py3.12 版本
- habitat_evaluation.py 同时 import rclpy + habitat_sim → 必须 py3.12 + 源码编译 habitat-sim

---

## 9. 当前已知限制

- **habitat-sim 装的是 0.3.3 main 分支**，不是 README 写的 0.3.1。原因是 0.3.1 源码与 py3.12 不兼容。API 有一处要 sed 打补丁（Dockerfile 已自动做）。
- **GroundingDINO 运行在 CPU 模式**（自定义 CUDA 扩展 `_C` 未编译）。检测速度慢一点，精度不受影响。
- BLIP2 权重不在仓库里，首次运行要下 ~2.6 GB（挂载到 `data/torch_cache` 持久化）。
