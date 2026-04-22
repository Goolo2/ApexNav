#!/bin/bash
# Entrypoint: source ROS2, wire up yolov7/GroundingDINO, exec user command.
set -e

source /opt/ros/jazzy/setup.bash

# Make VLM scripts find yolov7/ and GroundingDINO/ relative to the workspace.
# The source repo is bind-mounted, so we create links on each start (idempotent).
for name in yolov7 GroundingDINO; do
    [ -d "/opt/$name" ] && [ ! -e "/workspace/ApexNav/$name" ] && \
        ln -sfn "/opt/$name" "/workspace/ApexNav/$name" || true
done

# GroundingDINO source import path
export PYTHONPATH="/opt/GroundingDINO:/workspace/ApexNav:${PYTHONPATH:-}"

# If a colcon build exists, source it
if [ -f "/workspace/ApexNav/install/setup.bash" ]; then
    source /workspace/ApexNav/install/setup.bash
fi

cd /workspace/ApexNav
exec "$@"
