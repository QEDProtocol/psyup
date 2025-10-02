# QED Rollup CLI

A command-line interface for QED Rollup operations.

## Supported Platforms

- Ubuntu 22.04 (x86_64, aarch64)
- Ubuntu 24.04 (x86_64, aarch64)

## Installation

### Prerequisites

- Ubuntu 22.04 or Ubuntu 24.04
- curl (will be installed automatically if not present)
- sudo privileges

### Quick Installation

Run the following command to install QED Rollup CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/qed/psyup/main/install.sh | bash
```

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/qed/psyup.git
cd psyup
```

2. Make the install script executable:
```bash
chmod +x install.sh
```

3. Run the installation script:
```bash
./install.sh
```

### Installation Process

The installation script will:

1. **Detect your Ubuntu version** - Only Ubuntu 22.04 and 24.04 are supported
2. **Detect your architecture** - Supports x86_64 and aarch64/arm64
3. **Download the appropriate prebuilt binary** from the latest release
4. **Install the binary** to `/usr/local/bin/`
5. **Verify the installation** and make it available in your PATH

### Troubleshooting

#### Unsupported Ubuntu Version

If you're running an unsupported Ubuntu version, you'll see an error like:
```
[ERROR] Unsupported Ubuntu version: 20.04
[ERROR] This script only supports Ubuntu 22.04 and Ubuntu 24.04
```

**Solution**: Upgrade to Ubuntu 22.04 or 24.04, or use a supported distribution.

#### Unsupported Architecture

If you're running on an unsupported architecture, you'll see an error like:
```
[ERROR] Unsupported architecture: i386
[ERROR] This script only supports x86_64 and aarch64/arm64 architectures
```

**Solution**: Use a supported architecture (x86_64 or aarch64/arm64).

#### Permission Issues

If you encounter permission issues during installation:
```bash
sudo ./install.sh
```

#### Binary Not Found After Installation

If the binary is not found in your PATH after installation:
```bash
# Check if it's installed
ls -la /usr/local/bin/qed_rollup_cli

# Run directly
/usr/local/bin/qed_rollup_cli --help

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH="/usr/local/bin:$PATH"
```

## Usage

After installation, you can use the QED Rollup CLI:

```bash
# Check if installation was successful
qed_rollup_cli --help

# Run your commands
qed_rollup_cli [command] [options]
```

## Development

### Building from Source

If you need to build from source for unsupported platforms:

1. Clone the repository
2. Follow the build instructions in the source code
3. Install the built binary manually

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on supported platforms
5. Submit a pull request

## License

[Add your license information here]

## Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section above
- Ensure you're using a supported platform
```
