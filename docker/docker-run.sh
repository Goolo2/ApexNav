#!/bin/bash
# Launch ApexNav container with GPU + X11 + volume mounts.
# Mounts the host torch_cache so BLIP2's 2.6 GB weights survive container rm.
set -e

IMAGE=${IMAGE:-apexnav:jazzy}
NAME=${NAME:-apexnav}
REPO_DIR=$(cd "$(dirname "$0")/.." && pwd)

xhost +local:docker >/dev/null 2>&1 || true

if docker ps -a --format '{{.Names}}' | grep -q "^${NAME}$"; then
    docker start "${NAME}" >/dev/null
    exec docker exec -it "${NAME}" bash
fi

# Ensure cache dirs exist so the bind mounts succeed
mkdir -p "${REPO_DIR}/data/torch_cache/hub"
mkdir -p "${REPO_DIR}/data/hf_cache"

docker run -it --rm \
    --name "${NAME}" \
    --gpus all \
    --net=host \
    --ipc=host \
    --privileged \
    -e DISPLAY=${DISPLAY} \
    -e QT_X11_NO_MITSHM=1 \
    -e NVIDIA_DRIVER_CAPABILITIES=all \
    -e ROS_DOMAIN_ID=${ROS_DOMAIN_ID:-42} \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v "${REPO_DIR}":/workspace/ApexNav:rw \
    -v "${REPO_DIR}/data/torch_cache/hub":/root/.cache/torch/hub:rw \
    -v "${REPO_DIR}/data/hf_cache":/root/.cache/huggingface:rw \
    --device /dev/dri \
    "${IMAGE}" \
    bash
