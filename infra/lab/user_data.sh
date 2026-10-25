#!/bin/bash
# Installs every tool we need for the 15 days. Log: /var/log/cloud-init-output.log
set -euxo pipefail
export PATH=$PATH:/usr/local/bin

# 1. Update the OS and install base tools (strict=0: skip a package if it's not available)
dnf -y update
dnf -y install --setopt=strict=0 git docker jq tree make tar unzip wget vim bash-completion \
  python3.11 python3.11-pip bind-utils tcpdump lsof sysstat traceroute nmap-ncat \
  cronie nftables policycoreutils-python-utils
systemctl enable --now docker crond sysstat

# 2. Let ec2-user run docker without sudo; add the Compose and Buildx plugins
usermod -aG docker ec2-user
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
BUILDX=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/docker/buildx/releases/latest | sed 's#.*/##')
curl -fsSL "https://github.com/docker/buildx/releases/download/${BUILDX}/buildx-${BUILDX}.linux-amd64" \
  -o /usr/local/lib/docker/cli-plugins/docker-buildx
chmod +x /usr/local/lib/docker/cli-plugins/*

# 3. Kernel limits that multi-node kind clusters need
printf 'fs.inotify.max_user_watches = 524288\nfs.inotify.max_user_instances = 512\n' > /etc/sysctl.d/99-kind.conf
sysctl --system

# 4. Kubernetes tools: kubectl, kind, helm
curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -fsSLo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.29.0/kind-linux-amd64
chmod +x /usr/local/bin/kubectl /usr/local/bin/kind
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 5. Terraform (latest version)
TF=$(curl -fsSL https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version)
curl -fsSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF}/terraform_${TF}_linux_amd64.zip"
unzip -o /tmp/tf.zip terraform -d /usr/local/bin && rm -f /tmp/tf.zip

# 6. Trivy (security scanner for images)
curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# AWS CLI v2 is already part of Amazon Linux 2023.
touch /var/log/lab-setup-done
