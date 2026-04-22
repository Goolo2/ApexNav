#!/bin/bash
# Install NVIDIA Container Toolkit and enable GPU support in Docker.
# Requires sudo.
set -e

sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | sudo gpg --dearmor --batch --yes \
        -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
sudo chmod 644 /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
# sanity check: keyring must be non-empty
test -s /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
    || { echo "ERROR: keyring empty — gpgkey download failed"; exit 1; }

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
sudo usermod -aG docker "$USER"

echo ""
echo "DONE. Run 'newgrp docker' or log out/in so the docker group takes effect."
