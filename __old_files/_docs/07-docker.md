# Docker

## 1. Remove conflicting packages (if any)
```bash
sudo dnf remove -y docker \
  docker-client \
  docker-client-latest \
  docker-common \
  docker-latest \
  docker-latest-logrotate \
  docker-logrotate \
  docker-selinux \
  docker-engine-selinux \
  docker-engine
```

## 2. Add official Docker repository
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager \
  addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
```

## 3. Install Docker Engine + CLI + Compose plugin
```bash
sudo dnf install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

What this installs:
- docker (engine + CLI)
- docker compose (v2 plugin, not the old docker-compose Python binary)
- containerd runtime
- Buildx (required by many modern workflows)

## 4. Enable and start Docker daemon
```bash
sudo systemctl enable --now docker
```

Verify:
```bash
systemctl status docker
```

## 5. Post-install: run Docker without sudo (recommended)
Add your user to the docker group:
```bash
sudo usermod -aG docker $USER
```

Apply group change (log out and log back in, or reboot). If you want it
immediately in the current shell, run:
```bash
newgrp docker
```

Confirm your user is in the group:
```bash
groups
```

Verify:
```bash
docker run hello-world
```

If this works without sudo, permissions are correct.

## 6. Verify Docker Compose (v2)
```bash
docker compose version
```

Expected:
```bash
Docker Compose version v2.x.x
```
