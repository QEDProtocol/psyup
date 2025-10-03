#!/bin/bash

# QED Rollup CLI Installation Script
# Supports Ubuntu 22.04 and Ubuntu 24.04

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect Ubuntu version
detect_ubuntu_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [ "$ID" = "ubuntu" ]; then
            echo "$VERSION_ID"
        else
            echo "not_ubuntu"
        fi
    else
        echo "unknown"
    fi
}

# Function to get architecture
get_architecture() {
    case $(uname -m) in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

# Function to download and install qed_rollup_cli
install_qed_rollup_cli() {
    local version=$1
    local arch=$2
   # local download_url="https://github.com/qed/psyup/releases/latest/download/qed_rollup_cli_${version}_${arch}.tar.gz"
    local download_url="https://raw.githubusercontent.com/QEDProtocol/psyup/refs/heads/main/qed_rollup_cli_${version}_${arch}.tar.gz"
    local temp_dir=$(mktemp -d)
    local install_dir="/usr/local/bin"
    
    print_info "Downloading qed_rollup_cli for Ubuntu ${version} (${arch})..."
    
    # Download the release
    if ! curl -L -o "${temp_dir}/qed_rollup_cli.tar.gz" "$download_url"; then
        print_error "Failed to download qed_rollup_cli for Ubuntu ${version}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    print_info "Extracting qed_rollup_cli..."
    cd "$temp_dir"
    tar -xzf qed_rollup_cli.tar.gz
    
    # Check if binary exists
    if [ ! -f "qed_rollup_cli" ]; then
        print_error "qed_rollup_cli binary not found in the downloaded package"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    # Make binary executable
    chmod +x qed_rollup_cli
    
    # Install to system
    print_info "Installing qed_rollup_cli to ${install_dir}..."
    sudo cp qed_rollup_cli "$install_dir/"
    
    # Clean up
    rm -rf "$temp_dir"
    
    print_success "qed_rollup_cli installed successfully!"
}

# Main installation process
main() {
    print_info "QED Rollup CLI Installation Script"
    print_info "===================================="
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_warning "It's not recommended to run this script as root"
        read -p "Do you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
    fi
    
    # Detect Ubuntu version
    print_info "Detecting Ubuntu version..."
    ubuntu_version=$(detect_ubuntu_version)
    
    if [ "$ubuntu_version" = "not_ubuntu" ]; then
        print_error "This script only supports Ubuntu. Detected OS is not Ubuntu."
        exit 1
    elif [ "$ubuntu_version" = "unknown" ]; then
        print_error "Unable to detect Ubuntu version. Please run this script on Ubuntu 22.04 or 24.04."
        exit 1
    elif [ "$ubuntu_version" != "22.04" ] && [ "$ubuntu_version" != "24.04" ]; then
        print_error "Unsupported Ubuntu version: ${ubuntu_version}"
        print_error "This script only supports Ubuntu 22.04 and Ubuntu 24.04"
        exit 1
    fi
    
    print_success "Detected Ubuntu ${ubuntu_version}"
    
    # Get architecture
    arch=$(get_architecture)
    if [ "$arch" = "unsupported" ]; then
        print_error "Unsupported architecture: $(uname -m)"
        print_error "This script only supports x86_64 and aarch64/arm64 architectures"
        exit 1
    fi
    
    print_success "Detected architecture: ${arch}"
    
    # Check if curl is installed
    if ! command -v curl &> /dev/null; then
        print_info "curl is not installed. Installing curl..."
        sudo apt-get update
        sudo apt-get install -y curl
    fi
    
    # Install qed_rollup_cli
    install_qed_rollup_cli "$ubuntu_version" "$arch"
    
    # Verify installation
    print_info "Verifying installation..."
    if command -v qed_rollup_cli &> /dev/null; then
        print_success "qed_rollup_cli is now available in your PATH"
        print_info "You can run 'qed_rollup_cli --help' to see available commands"
    else
        print_warning "qed_rollup_cli was installed but may not be in your PATH"
        print_info "Try running '/usr/local/bin/qed_rollup_cli --help'"
    fi
    
    print_success "Installation completed successfully!"
}

# Run main function
main "$@"
