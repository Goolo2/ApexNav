#!/bin/bash
# Configure Docker registry mirrors for faster pulls in China.
# Also preserves NVIDIA runtime config.
set -e

sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "runtimes": {
    "nvidia": {
      "path": "nvidia-container-runtime",
      "runtimeArgs": []
    }
  },
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://mirror.ccs.tencentyun.com"
  ]
}
EOF

sudo systemctl restart docker
echo "DONE. daemon.json:"
cat /etc/docker/daemon.json
