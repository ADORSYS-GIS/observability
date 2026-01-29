#!/bin/bash
set -e

BINARY_NAME="argocd-agentctl"
INSTALL_PATH="/usr/local/bin/${BINARY_NAME}"

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ARCH="linux-amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH="linux-arm64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi
GITHUB_REPO="argoproj-labs/argocd-agent"
VERSION="v0.5.3"

echo "==> Installing argocd-agentctl (${VERSION}) to /usr/local/bin..."

# Download URL
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION}/argocd-agentctl_${ARCH}"

echo "Downloading from: ${DOWNLOAD_URL}"

# Download to temp location
TEMP_FILE=$(mktemp)
curl -L "${DOWNLOAD_URL}" -o "${TEMP_FILE}"

# Make it executable
chmod +x "${TEMP_FILE}"

# Move to /usr/local/bin (requires sudo)
echo "Moving binary to ${INSTALL_PATH} (requires sudo)..."
sudo mv "${TEMP_FILE}" "${INSTALL_PATH}"

# Verify installation
if [ -x "${INSTALL_PATH}" ]; then
  echo "✅ Successfully installed ${BINARY_NAME} to ${INSTALL_PATH}"
  "${INSTALL_PATH}" version || echo "Installed: ${VERSION}"
else
  echo "❌ ERROR: Installation failed"
  exit 1
fi

echo "Installation complete!"
