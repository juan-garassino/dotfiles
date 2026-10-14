#!/usr/bin/env bash
# linux-tools.sh — the Linux counterpart of the Brewfile CLI toolchain (Debian/Ubuntu, apt).
# Run by install.sh on apt systems. Idempotent: every tool is skipped if already on PATH.
# Third-party apt repos are checked for this release's codename first; if a vendor hasn't
# published it yet (new Ubuntu releases lag), fall back to the Ubuntu archive or the last LTS.
set -u
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
ARCH="$(dpkg --print-architecture)"
have() { command -v "$1" >/dev/null 2>&1; }
repo_has() { curl -fsI "$1/dists/$2/Release" >/dev/null 2>&1; }
sudo install -m 0755 -d /etc/apt/keyrings

# WSL: Docker Engine needs systemd as PID 1 (/etc/wsl.conf [boot] systemd=true + `wsl --shutdown`).
# Docker Desktop's WSL integration also works — then `docker` is already on PATH and this is skipped.
if [ "${IS_WSL:-0}" = 1 ] && [ "$(ps -p 1 -o comm= 2>/dev/null)" != systemd ]; then
  if ! grep -q 'systemd *= *true' /etc/wsl.conf 2>/dev/null; then
    printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
  echo "  🪟 WSL: systemd enabled in /etc/wsl.conf — run 'wsl --shutdown' in Windows PowerShell,"
  echo "     reopen Ubuntu, then re-run install.sh so Docker can start."
fi

# Docker Engine + compose plugin (official repo; Ubuntu's docker.io as fallback)
if ! have docker; then
  echo "  📦 docker..."
  if repo_has https://download.docker.com/linux/ubuntu "$CODENAME"; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $CODENAME stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    echo "  ↪ docker repo has no '$CODENAME' yet — using Ubuntu's docker.io"
    sudo apt-get install -y docker.io docker-compose-v2 || sudo apt-get install -y docker.io
  fi
  sudo usermod -aG docker "$(id -un)" 2>/dev/null && echo "  👥 $(id -un) added to docker group (re-login to apply)"
fi

# Google Cloud CLI (codename-independent repo)
if ! have gcloud; then
  echo "  📦 gcloud..."
  curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/cloud.google.gpg
  echo "deb [signed-by=/etc/apt/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y google-cloud-cli
fi

# Terraform (HashiCorp repo; falls back to the noble suite — static binaries)
if ! have terraform; then
  echo "  📦 terraform..."
  hc_suite="$CODENAME"; repo_has https://apt.releases.hashicorp.com "$hc_suite" || hc_suite=noble
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp.gpg
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $hc_suite main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y terraform
fi

# kubectl (pkgs.k8s.io, codename-independent) + helm (official script)
if ! have kubectl; then
  echo "  📦 kubectl..."
  K8S=v1.34
  curl -fsSL "https://pkgs.k8s.io/core:/stable:/$K8S/deb/Release.key" | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes.gpg
  echo "deb [signed-by=/etc/apt/keyrings/kubernetes.gpg] https://pkgs.k8s.io/core:/stable:/$K8S/deb/ /" \
    | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
  sudo apt-get update -y && sudo apt-get install -y kubectl
fi
have helm || { echo "  📦 helm..."; curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >/dev/null; }

# AWS CLI v2 (work only; Ubuntu dropped the apt package)
if ! have aws; then
  echo "  📦 awscli v2..."
  tmp="$(mktemp -d)"
  case "$ARCH" in arm64) a=aarch64 ;; *) a=x86_64 ;; esac
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$a.zip" -o "$tmp/aws.zip" \
    && unzip -q "$tmp/aws.zip" -d "$tmp" && sudo "$tmp/aws/install" >/dev/null && echo "  ✅ aws"
  rm -rf "$tmp"
fi

# Warp terminal (official repo, amd64; arm64 → .deb from warp.dev). Settings: install.sh step 8b.
if [ "${IS_WSL:-0}" = 1 ]; then
  echo "  🪟 WSL: use Warp for Windows (https://www.warp.dev/download) — not the Linux app"
elif ! have warp-terminal; then
  if [ "$ARCH" = amd64 ]; then
    echo "  📦 warp..."
    curl -fsSL https://releases.warp.dev/linux/keys/warp.asc | sudo gpg --dearmor --yes -o /etc/apt/keyrings/warpdotdev.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/warpdotdev.gpg] https://releases.warp.dev/linux/deb stable main" \
      | sudo tee /etc/apt/sources.list.d/warpdotdev.list >/dev/null
    sudo apt-get update -y && sudo apt-get install -y warp-terminal
  else
    echo "  ⚠️  warp: no arm64 apt repo — install the arm64 .deb from https://www.warp.dev/download"
  fi
fi

# Kubernetes local clusters + CI/dev single binaries (Brewfile: minikube k3d act mkcert runpodctl cloud-sql-proxy)
case "$ARCH" in arm64) GOARCH=arm64 ;; *) GOARCH=amd64 ;; esac
if ! have minikube; then
  echo "  📦 minikube..."
  tmp="$(mktemp -d)"; curl -fsSL -o "$tmp/minikube.deb" "https://storage.googleapis.com/minikube/releases/latest/minikube_latest_${GOARCH}.deb" \
    && sudo apt-get install -y "$tmp/minikube.deb" >/dev/null; rm -rf "$tmp"
fi
have k3d || { echo "  📦 k3d..."; curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | sudo bash >/dev/null; }
have act || { echo "  📦 act..."; curl -fsSL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin >/dev/null; }
have runpodctl || { echo "  📦 runpodctl..."; curl -fsSL cli.runpod.net | sudo bash >/dev/null 2>&1 || echo "  ⚠️  runpodctl install failed"; }
if ! have cloud-sql-proxy; then
  echo "  📦 cloud-sql-proxy..."
  tag="$(curl -fsSL https://api.github.com/repos/GoogleCloudPlatform/cloud-sql-proxy/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)"
  [ -n "$tag" ] && sudo curl -fsSL -o /usr/local/bin/cloud-sql-proxy \
    "https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/${tag}/cloud-sql-proxy.linux.${GOARCH}" \
    && sudo chmod +x /usr/local/bin/cloud-sql-proxy
fi

# llm CLI (uv tool, same as everything Python)
have llm || { have uv && uv tool install llm >/dev/null 2>&1 && echo "  ✅ llm (uv tool)"; }

# ollama — heavy (systemd service + GPU libs): skipped in MINIMAL rehearsals
if [ "${DOTFILES_MINIMAL:-0}" != 1 ] && ! have ollama; then
  echo "  📦 ollama..."; curl -fsSL https://ollama.com/install.sh | sh >/dev/null 2>&1 || echo "  ⚠️  ollama install failed"
fi

echo "  ✅ Linux toolchain done"
