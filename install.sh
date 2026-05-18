#!/usr/bin/env bash
# psyup installer — bootstraps ~/.psy and drops the psyup script.
# Usage: curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | sh
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

mkdir -p "$PSY_HOME/bin" "$PSY_HOME/toolchains" "$PSY_HOME/templates" "$PSY_HOME/lib"

fetch() {
    # fetch <remote-path> <local-path>
    local url="$RAW_BASE/$1"
    say "fetching $1"
    curl -fsSL "$url" -o "$2" || die "failed to download $url"
}

fetch psyup           "$PSY_HOME/bin/psyup"
chmod +x "$PSY_HOME/bin/psyup"

for f in common.sh cmd_install.sh cmd_new.sh cmd_build.sh cmd_deploy.sh; do
    fetch "lib/$f" "$PSY_HOME/lib/$f"
done
fetch config.json "$PSY_HOME/config.json"
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
# psyup shell integration. source this file to add psyup to PATH
# and expose the active PSY toolchain's std library.
case ":${PATH}:" in
    *:"$HOME/.psy/bin":*) ;;
    *) export PATH="$HOME/.psy/bin:$PATH" ;;
esac

# DARGO_STD_PATH and RPC_CONFIG are rewritten by `psyup install` to point at
# files installed from the active toolchain. Leave the marker lines as-is.
# DARGO_STD_PATH=__PSYUP_MANAGED__
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

# Append source line to shell rc (idempotent).
append_rc() {
    local rc="$1" line='. "$HOME/.psy/env"'
    [ -f "$rc" ] || return 0
    if ! grep -Fq "$line" "$rc"; then
        printf '\n# added by psyup installer\n%s\n' "$line" >> "$rc"
        say "updated $rc"
    fi
}

case "${SHELL:-}" in
    *zsh*)  append_rc "$HOME/.zshrc"  ;;
    *bash*) append_rc "$HOME/.bashrc" ; append_rc "$HOME/.bash_profile" ;;
    *)      append_rc "$HOME/.profile" ;;
esac

cat <<EOF

psyup installed to $PSY_HOME/bin/psyup

Next steps:
    1. Reload your shell, or run:  source $PSY_HOME/env
    2. Install the PSY toolchain:  psyup install
    3. Create a new project:       psyup new my-contract

EOF
