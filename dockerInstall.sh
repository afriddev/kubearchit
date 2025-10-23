sudo apt update -y
sudo apt install -y curl apt-transport-https ca-certificates conntrack

curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER && newgrp docker
docker --version