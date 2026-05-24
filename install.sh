#!/usr/bin/env bash
# psyup installer — bootstraps ~/.psy and drops the psyup script.
# Usage: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | bash
set -eu

PSYUP_REPO="${PSYUP_REPO:-QEDProtocol/psyup}"
PSYUP_BRANCH="${PSYUP_BRANCH:-feat/parth-generic-v1}"
PSY_HOME="${PSY_HOME:-$HOME/.psy}"
PSYUP_DEFAULT_NETWORK="${PSYUP_DEFAULT_NETWORK:-localhost}"
RAW_BASE="https://raw.githubusercontent.com/${PSYUP_REPO}/${PSYUP_BRANCH}"

say()  { printf 'psyup: %s\n' "$*"; }
die()  { printf 'psyup: error: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
need curl
need uname
need tar
need python3

detect_triple() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)
    case "$os" in
        Darwin) os=apple-darwin ;;
        Linux)  os=unknown-linux-gnu ;;
        *) die "unsupported OS: $os (only macOS and Linux supported)" ;;
    esac
    case "$arch" in
        x86_64|amd64) arch=x86_64 ;;
        arm64|aarch64) arch=aarch64 ;;
        *) die "unsupported arch: $arch" ;;
    esac
    printf '%s-%s\n' "$arch" "$os"
}

TRIPLE=$(detect_triple)
say "detected platform: $TRIPLE"

if [ -d "$PSY_HOME" ] && [ -f "$PSY_HOME/bin/psyup" ]; then
    say "psyup is already installed at $PSY_HOME"
    if [ -d "$PSY_HOME/keystore" ]; then
        say "found existing keystore at $PSY_HOME/keystore (will be preserved)"
        say "overwriting non-keystore files in 5 seconds (Ctrl+C to abort)"
    else
        say "overwriting in 5 seconds (Ctrl+C to abort)"
    fi
    sleep 5
fi

mkdir -p "$PSY_HOME/bin" "$PSY_HOME/toolchains" "$PSY_HOME/templates" "$PSY_HOME/lib"

fetch() {
    # fetch <remote-path> <local-path>
    local url="$RAW_BASE/$1"
    say "fetching $1"
    local tmp_file
    tmp_file=$(mktemp)
    if curl -fsSL "$url" -o "$tmp_file"; then
        # only overwrite if content changed
        if [ -f "$2" ] && cmp -s "$tmp_file" "$2"; then
            rm -f "$tmp_file"
            return 0
        fi
        mv "$tmp_file" "$2"
    else
        rm -f "$tmp_file"
        die "failed to download $url"
    fi
}

fetch psyup           "$PSY_HOME/bin/psyup"
chmod +x "$PSY_HOME/bin/psyup"

for f in common.sh cmd_install.sh cmd_new.sh cmd_build.sh cmd_deploy.sh cmd_init.sh cmd_worker.sh; do
    fetch "lib/$f" "$PSY_HOME/lib/$f"
done
fetch config.json "$PSY_HOME/config.json"
python3 - "$PSY_HOME/config.json" "$PSYUP_DEFAULT_NETWORK" <<'PY' >/dev/null || die "invalid default network '$PSYUP_DEFAULT_NETWORK' for $PSY_HOME/config.json"
import json, sys
cfg = json.load(open(sys.argv[1]))
network = sys.argv[2]
nets = cfg.get("networks", {})
if network not in nets:
    available = ", ".join(sorted(nets.keys())) if isinstance(nets, dict) and nets else "<none>"
    print(f"invalid network '{network}' (available: {available})", file=sys.stderr)
    sys.exit(1)
PY
tmp_config=$(mktemp)
awk -v n="$PSYUP_DEFAULT_NETWORK" '
    /^[[:space:]]*"defaultNetwork"[[:space:]]*:/ {
        comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
        indent = $0
        sub(/"defaultNetwork".*$/, "", indent)
        print indent "\"defaultNetwork\": \"" n "\"" comma
        next
    }
    { print }
' "$PSY_HOME/config.json" > "$tmp_config" && mv "$tmp_config" "$PSY_HOME/config.json"

cat > "$PSY_HOME/env" <<'EOF'
# psyup shell integration for POSIX shells.
# PATH is normally added via your shell rc during install.sh; this file is
# mainly for manual use in bash/zsh/sh. fish users should not source it.
case ":${PATH}:" in
    *:"$HOME/.psy/bin":*) ;;
    *) export PATH="$HOME/.psy/bin:$PATH" ;;
esac
export RPC_CONFIG="$HOME/.psy/config.json"
EOF

if [ ! -f "$PSY_HOME/settings.toml" ]; then
    cat > "$PSY_HOME/settings.toml" <<EOF
# psyup user settings
active = ""
default_network = "$PSYUP_DEFAULT_NETWORK"
EOF
else
    tmp_settings=$(mktemp)
    awk -v n="$PSYUP_DEFAULT_NETWORK" '
        /^default_network[[:space:]]*=/ {
            print "default_network = \"" n "\""
            seen_network=1
            next
        }
        { print }
        END {
            if (seen_network != 1) print "default_network = \"" n "\""
        }
    ' "$PSY_HOME/settings.toml" > "$tmp_settings" && mv "$tmp_settings" "$PSY_HOME/settings.toml"
fi

# Detect shell and persist psyup on PATH for future shell sessions.
SHELL_BIN="${SHELL:-sh}"
SHELL_BIN="${SHELL_BIN##*/}"

if [[ "$SHELL_BIN" == "fish" ]]; then
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    mkdir -p "$HOME/.config/fish"
    if ! grep -Fq 'fish_add_path -a $HOME/.psy/bin' "$FISH_CONFIG" 2>/dev/null; then
        printf '\n# added by psyup installer\nfish_add_path -a $HOME/.psy/bin\n' >> "$FISH_CONFIG"
        say "added psyup to fish config: $FISH_CONFIG"
    fi
elif [[ "$SHELL_BIN" == "zsh" ]]; then
    ZSH_ENV="$HOME/.zshenv"
    if ! grep -Fq 'export PATH="$HOME/.psy/bin:$PATH"' "$ZSH_ENV" 2>/dev/null; then
        printf '\n# added by psyup installer\nexport PATH="$HOME/.psy/bin:$PATH"\n' >> "$ZSH_ENV"
        say "added psyup to zsh config: $ZSH_ENV"
    fi
elif [[ "$SHELL_BIN" == "bash" ]]; then
    BASH_RC="$HOME/.bashrc"
    BASH_PROFILE="$HOME/.bash_profile"
    if ! grep -Fq 'export PATH="$HOME/.psy/bin:$PATH"' "$BASH_RC" 2>/dev/null; then
        printf '\n# added by psyup installer\nexport PATH="$HOME/.psy/bin:$PATH"\n' >> "$BASH_RC"
        say "added psyup to bash config: $BASH_RC"
    fi
    if [ -f "$BASH_PROFILE" ] && ! grep -Fq 'export PATH="$HOME/.psy/bin:$PATH"' "$BASH_PROFILE" 2>/dev/null; then
        printf '\n# added by psyup installer\nexport PATH="$HOME/.psy/bin:$PATH"\n' >> "$BASH_PROFILE"
        say "added psyup to bash config: $BASH_PROFILE"
    fi
else
    PROFILE="$HOME/.profile"
    if ! grep -Fq 'export PATH="$HOME/.psy/bin:$PATH"' "$PROFILE" 2>/dev/null; then
        printf '\n# added by psyup installer\nexport PATH="$HOME/.psy/bin:$PATH"\n' >> "$PROFILE"
        say "added psyup to shell config: $PROFILE"
    fi
fi

# install toolchain
say "installing PSY toolchain..."
PSY_HOME="$PSY_HOME" "$PSY_HOME/bin/psyup" install
say ""

say ""
say "psyup installed to $PSY_HOME/bin/psyup"
say ""
say "Please restart your terminal or run:"
say '    export PATH="$HOME/.psy/bin:$PATH"'
say ""
say "Next steps:"
say "    1. Create a new project:       psyup new my-contract"
say "    2. Create a wallet:            psyup init"
say "    3. Compile the contract:       cd my-contract/contract && psyup build"
