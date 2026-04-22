# ApexNav ROS2 Jazzy — Dockerfile
# Dual Python: conda apexnav (py3.9) for VLM services
#              system py3.12 for habitat_evaluation + rclpy + habitat-sim (source build)
# Base: CUDA 12.8 + Ubuntu 24.04 (ROS2 Jazzy + RTX 5090 sm_120)
FROM nvidia/cuda:12.8.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    TZ=Asia/Shanghai \
    ROS_DISTRO=jazzy \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    CONDA_DIR=/opt/miniconda3 \
    WS=/workspace/ApexNav

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ================================================================
# PART A: Base system + ROS2 + conda env (for VLM services)
# ================================================================

# ---------- 1. Ubuntu apt mirror (Aliyun, faster in CN) ----------
RUN if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then \
        sed -i 's#http://archive.ubuntu.com#https://mirrors.aliyun.com#g; \
                s#http://security.ubuntu.com#https://mirrors.aliyun.com#g; \
                s#http://ports.ubuntu.com#https://mirrors.aliyun.com#g' \
            /etc/apt/sources.list.d/ubuntu.sources; \
    fi && \
    if [ -f /etc/apt/sources.list ]; then \
        sed -i 's#http://archive.ubuntu.com#https://mirrors.aliyun.com#g; \
                s#http://security.ubuntu.com#https://mirrors.aliyun.com#g' \
            /etc/apt/sources.list; \
    fi

# ---------- 2. System deps (incl. habitat-sim C++ build deps) ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales curl wget git gnupg2 lsb-release ca-certificates software-properties-common \
        build-essential cmake pkg-config ninja-build \
        libarmadillo-dev libompl-dev libeigen3-dev \
        libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 \
        libegl1 libgles2 libglvnd0 libglx0 \
        libjpeg-dev libglm-dev libegl1-mesa-dev mesa-utils xorg-dev freeglut3-dev \
        python3-pip python3-dev python3-full \
        tmux vim sudo \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ---------- 3. ROS2 Jazzy (Tsinghua mirror) ----------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        https://mirrors.tuna.tsinghua.edu.cn/ros2/ubuntu $(lsb_release -cs) main" \
        > /etc/apt/sources.list.d/ros2.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-desktop \
        ros-jazzy-cv-bridge ros-jazzy-pcl-conversions \
        ros-jazzy-message-filters ros-jazzy-tf2-ros ros-jazzy-tf2-geometry-msgs \
        ros-jazzy-visualization-msgs ros-jazzy-nav-msgs \
        ros-jazzy-osqp-vendor \
        python3-colcon-common-extensions python3-rosdep python3-argcomplete \
    && rosdep init && rosdep update \
    && rm -rf /var/lib/apt/lists/*

# ---------- 4. Miniconda + conda env apexnav (py3.9, for VLM services) ----------
RUN wget -q https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/mc.sh \
    && bash /tmp/mc.sh -b -p ${CONDA_DIR} && rm /tmp/mc.sh
ENV PATH=${CONDA_DIR}/bin:${PATH}

# Conda mirror (Tsinghua TUNA). aihabitat channel only on conda.anaconda.org.
RUN cat > /root/.condarc <<'EOF'
channels:
  - defaults
show_channel_urls: true
remote_connect_timeout_secs: 60
remote_read_timeout_secs: 120
remote_max_retries: 10
remote_backoff_factor: 2
default_channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/main
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/r
custom_channels:
  conda-forge: https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud
EOF

WORKDIR ${WS}
COPY apexnav_environment.yaml /tmp/apexnav_environment.yaml
RUN conda env create -f /tmp/apexnav_environment.yaml \
    && conda clean -afy

# Install VLM deps into conda env
SHELL ["conda", "run", "--no-capture-output", "-n", "apexnav", "/bin/bash", "-c"]

ARG PIP_PROXY=""

# PyTorch cu128 for conda env (VLM services use GPU via conda py3.9)
RUN if [ -n "$PIP_PROXY" ]; then \
        HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" \
        pip install --no-cache-dir --timeout 600 --retries 10 \
            --index-url https://pypi.org/simple/ \
            --extra-index-url https://download.pytorch.org/whl/cu128/ \
            torch torchvision torchaudio; \
    else \
        pip install --no-cache-dir --timeout 600 --retries 10 \
            --index-url https://mirrors.aliyun.com/pypi/simple/ \
            --extra-index-url https://download.pytorch.org/whl/cu128/ \
            --trusted-host mirrors.aliyun.com \
            torch torchvision torchaudio; \
    fi

# salesforce-lavis + spacy + tf-transformations + seaborn + mobile_sam for VLMs
RUN if [ -n "$PIP_PROXY" ]; then \
        HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" \
        PIP_CONFIG_FILE=/dev/null PIP_INDEX_URL=https://pypi.org/simple/ PIP_DEFAULT_TIMEOUT=600 \
        pip install --no-cache-dir --retries 10 \
            transforms3d "spacy<3.8.13" salesforce-lavis==1.0.2 \
            seaborn flask \
            git+https://github.com/DLu/tf_transformations.git \
            git+https://github.com/ChaoningZhang/MobileSAM.git; \
    else \
        pip install --no-cache-dir --timeout 600 --retries 10 \
            transforms3d "spacy<3.8.13" salesforce-lavis==1.0.2 \
            seaborn flask \
            git+https://github.com/DLu/tf_transformations.git \
            git+https://github.com/ChaoningZhang/MobileSAM.git; \
    fi

# ---------- 5. External code: yolov7 + GroundingDINO (into conda env) ----------
WORKDIR /opt
RUN if [ -n "$PIP_PROXY" ]; then HTTPS_PROXY="$PIP_PROXY" HTTP_PROXY="$PIP_PROXY"; fi && \
    git clone https://github.com/WongKinYiu/yolov7.git \
    && sed -i 's/torch.load(w, map_location=map_location)/torch.load(w, weights_only=False, map_location=map_location)/g' \
        /opt/yolov7/models/experimental.py

RUN if [ -n "$PIP_PROXY" ]; then HTTPS_PROXY="$PIP_PROXY" HTTP_PROXY="$PIP_PROXY"; fi && \
    git clone https://github.com/IDEA-Research/GroundingDINO.git \
    && cd GroundingDINO \
    && (CUDA_HOME=/usr/local/cuda pip install --no-build-isolation -e . || \
        echo "WARN: GroundingDINO CUDA ext build failed; runs in CPU mode (still works)")

# ================================================================
# PART B: System Python 3.12 (for habitat_evaluation + rclpy)
# ================================================================
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pip mirror for system python
RUN mkdir -p /root/.pip \
    && printf '[global]\nindex-url = https://mirrors.aliyun.com/pypi/simple/\ntrusted-host = mirrors.aliyun.com\n' > /root/.pip/pip.conf

# ---------- 6. PyTorch 2.9.1+cu128 for system py3.12 ----------
RUN if [ -n "$PIP_PROXY" ]; then \
        HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" PIP_CONFIG_FILE=/dev/null \
        /usr/bin/python3.12 -m pip install --no-cache-dir --timeout 900 --retries 10 \
            --index-url https://download.pytorch.org/whl/cu128 \
            torch==2.9.1 torchvision torchaudio; \
    else \
        /usr/bin/python3.12 -m pip install --no-cache-dir --timeout 900 --retries 10 \
            --index-url https://download.pytorch.org/whl/cu128 \
            --trusted-host download.pytorch.org \
            torch==2.9.1 torchvision torchaudio; \
    fi

# ---------- 7. Python deps for habitat_evaluation (system py3.12) ----------
RUN if [ -n "$PIP_PROXY" ]; then \
        HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" PIP_CONFIG_FILE=/dev/null \
        PIP_INDEX_URL=https://pypi.org/simple/ PIP_DEFAULT_TIMEOUT=900 \
        /usr/bin/python3.12 -m pip install --no-cache-dir --retries 10 \
            --ignore-installed numpy blinker \
            "numpy==1.26.4" \
            transforms3d seaborn prettytable hydra-core flask \
            openai ollama \
            transformers==4.40.2 tokenizers \
            omegaconf iopath fairscale einops timm==0.4.12 \
            opencv-python-headless decord ftfy contexttimer ipython pandas \
            pycocoevalcap pycocotools scikit-image plotly opendatasets \
            sentencepiece webdataset "spacy<3.8.13" \
        && HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" PIP_CONFIG_FILE=/dev/null \
           PIP_INDEX_URL=https://pypi.org/simple/ \
           /usr/bin/python3.12 -m pip install --no-cache-dir --no-deps salesforce-lavis==1.0.2 \
        && HTTP_PROXY="$PIP_PROXY" HTTPS_PROXY="$PIP_PROXY" \
           /usr/bin/python3.12 -m pip install --no-cache-dir \
             git+https://github.com/DLu/tf_transformations.git \
             git+https://github.com/ChaoningZhang/MobileSAM.git; \
    else \
        /usr/bin/python3.12 -m pip install --no-cache-dir --retries 10 \
            --ignore-installed numpy blinker \
            "numpy==1.26.4" transforms3d seaborn prettytable hydra-core flask \
            openai ollama transformers==4.40.2 omegaconf iopath fairscale einops \
            timm==0.4.12 opencv-python-headless decord ftfy contexttimer ipython \
            pandas pycocoevalcap pycocotools scikit-image plotly opendatasets \
            sentencepiece webdataset "spacy<3.8.13" \
        && /usr/bin/python3.12 -m pip install --no-cache-dir --no-deps salesforce-lavis==1.0.2 \
        && /usr/bin/python3.12 -m pip install --no-cache-dir \
             git+https://github.com/DLu/tf_transformations.git \
             git+https://github.com/ChaoningZhang/MobileSAM.git; \
    fi

# ---------- 8. habitat-lab (main branch, py3.12 compatible) for system py3.12 ----------
WORKDIR /opt
RUN if [ -n "$PIP_PROXY" ]; then HTTPS_PROXY="$PIP_PROXY" HTTP_PROXY="$PIP_PROXY"; fi && \
    git clone https://github.com/facebookresearch/habitat-lab.git \
    && sed -i 's/self\._sim\.agents\[0\]\.sensors/self._sim.agents[0]._sensors/g' \
        /opt/habitat-lab/habitat-lab/habitat/tasks/nav/nav.py \
    && PIP_CONFIG_FILE=/dev/null PIP_INDEX_URL=https://pypi.org/simple/ \
       /usr/bin/python3.12 -m pip install --no-cache-dir --no-build-isolation \
           -e /opt/habitat-lab/habitat-lab -e /opt/habitat-lab/habitat-baselines \
    && /usr/bin/python3.12 -m pip install --no-cache-dir "numpy==1.26.4" --force-reinstall

# ---------- 9. habitat-sim (source build for py3.12, ~30-60 min) ----------
RUN if [ -n "$PIP_PROXY" ]; then HTTPS_PROXY="$PIP_PROXY" HTTP_PROXY="$PIP_PROXY"; fi && \
    git clone --branch stable --recursive https://github.com/facebookresearch/habitat-sim.git \
    && cd /opt/habitat-sim \
    && PIP_CONFIG_FILE=/dev/null PIP_INDEX_URL=https://pypi.org/simple/ \
       /usr/bin/python3.12 -m pip install --no-cache-dir -r requirements.txt \
    && /usr/bin/python3.12 setup.py install --bullet --with-cuda \
    && PIP_CONFIG_FILE=/dev/null PIP_INDEX_URL=https://pypi.org/simple/ \
       /usr/bin/python3.12 -m pip install --no-cache-dir --no-build-isolation \
           /opt/habitat-sim/build/deps/magnum-bindings/src/python

# ================================================================
# PART C: C++ build deps + workspace setup
# ================================================================

# ---------- 10. OsqpEigen (C++ wrapper for trajectory_manager) ----------
RUN cd /tmp && git clone --depth 1 --branch v0.8.1 https://github.com/robotology/osqp-eigen.git \
    && cd osqp-eigen && mkdir build && cd build \
    && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -Dosqp_DIR=/opt/ros/jazzy/lib/cmake/osqp \
    && make -j$(nproc) install \
    && cd / && rm -rf /tmp/osqp-eigen

# ---------- 11. Workspace + entrypoint ----------
WORKDIR ${WS}
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
