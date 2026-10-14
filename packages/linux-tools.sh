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

# llm CLI (uv tool, same as everything Python)
have llm || { have uv && uv tool install llm >/dev/null 2>&1 && echo "  ✅ llm (uv tool)"; }

# ollama — heavy (systemd service + GPU libs): skipped in MINIMAL rehearsals
if [ "${DOTFILES_MINIMAL:-0}" != 1 ] && ! have ollama; then
  echo "  📦 ollama..."; curl -fsSL https://ollama.com/install.sh | sh >/dev/null 2>&1 || echo "  ⚠️  ollama install failed"
fi

echo "  ✅ Linux toolchain done (on demand, not installed: act k3d minikube mkcert runpodctl cloud-sql-proxy)"
