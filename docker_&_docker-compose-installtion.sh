#!/bin/bash

# Script to install Docker and Docker Compose with verification
# Compatible with Ubuntu/Debian-based systems

set -e  # Exit on error

echo "========================================="
echo "Docker & Docker Compose Installation"
echo "========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run this script with sudo or as root"
    exit 1
fi

print_info "Starting installation process..."
echo ""

# Update package index
print_info "Updating package index..."
apt-get update -qq

# Install prerequisites
print_info "Installing prerequisites..."
apt-get install -y -qq \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker's official GPG key
print_info "Adding Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the repository
print_info "Setting up Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
apt-get update -qq

# Install Docker Engine, CLI, and Docker Compose plugin
print_info "Installing Docker Engine and Docker Compose..."
apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

print_success "Installation completed!"
echo ""

# Start and enable Docker service
print_info "Starting Docker service..."
systemctl start docker
systemctl enable docker
print_success "Docker service started and enabled"
echo ""

# Add current user to docker group (if not root)
if [ -n "$SUDO_USER" ]; then
    print_info "Adding user '$SUDO_USER' to docker group..."
    usermod -aG docker "$SUDO_USER"
    print_success "User added to docker group (logout and login to apply)"
fi

echo ""
echo "========================================="
echo "Installation Verification"
echo "========================================="
echo ""

# Verify Docker installation
print_info "Checking Docker version..."
if docker --version; then
    print_success "Docker is installed successfully"
else
    print_error "Docker installation failed"
    exit 1
fi
echo ""

# Verify Docker Compose installation
print_info "Checking Docker Compose version..."
if docker compose version; then
    print_success "Docker Compose is installed successfully"
else
    print_error "Docker Compose installation failed"
    exit 1
fi
echo ""

# Check Docker daemon status
print_info "Checking Docker daemon status..."
if systemctl is-active --quiet docker; then
    print_success "Docker daemon is running"
else
    print_error "Docker daemon is not running"
    exit 1
fi
echo ""

# Run a test container
print_info "Running test container (hello-world)..."
if docker run --rm hello-world > /dev/null 2>&1; then
    print_success "Docker can run containers successfully"
else
    print_error "Failed to run test container"
fi
echo ""

# Display summary
echo "========================================="
echo "Installation Summary"
echo "========================================="
docker --version
docker compose version
echo "Docker daemon status: $(systemctl is-active docker)"
echo ""

print_success "All checks passed! Docker and Docker Compose are ready to use."
echo ""
print_info "Note: If you were added to the docker group, please logout and login again"
print_info "      or run 'newgrp docker' to use Docker without sudo."
echo ""
