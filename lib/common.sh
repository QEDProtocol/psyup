# Shared helpers for psyup. Sourced, not executed.

PSY_HOME="${PSY_HOME:-$HOME/.psy}"
PSYUP_TOOLCHAIN_REPO="${PSYUP_TOOLCHAIN_REPO:-QEDProtocol/psyup}"
PSYUP_BOILERPLATE_REPO="${PSYUP_BOILERPLATE_REPO:-PsyProtocol/psy-template}"
PSYUP_DEFAULT_TEMPLATE="${PSYUP_DEFAULT_TEMPLATE:-dapp}"

say()  { printf 'psyup: %s\n' "$*"; }
warn() { printf 'psyup: warning: %s\n' "$*" >&2; }
die()  { printf 'psyup: error: %s\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

detect_triple() {
    local os arch
    os=$(uname -s)
    arch=$(uname -m)
    case "$os" in
        Darwin) os=apple-darwin ;;
        Linux)  os=unknown-linux-gnu ;;
        *) die "unsupported OS: $os" ;;
    esac
    case "$arch" in
        x86_64|amd64) arch=x86_64 ;;
        arm64|aarch64) arch=aarch64 ;;
        *) die "unsupported arch: $arch" ;;
    esac
    printf '%s-%s\n' "$arch" "$os"
}

sha256_verify() {
    # sha256_verify <file> <expected-hex>
    local file=$1 expected=$2 actual
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        die "neither sha256sum nor shasum found"
    fi
    [ "$actual" = "$expected" ] || die "checksum mismatch for $file (got $actual, expected $expected)"
}

# Read a simple top-level `key = "value"` from a TOML-ish file. Not a real parser.
settings_get() {
    local key=$1 file="$PSY_HOME/settings.toml"
    [ -f "$file" ] || { echo ""; return 0; }
    awk -v k="$key" '
        $1 == k && $2 == "=" {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/^"|"$/, "")
            print
            exit
        }
    ' "$file"
}

# Read the current default network from config.json.
# Uses PSYUP_CONFIG env var if set, otherwise falls back to $PSY_HOME/config.json.
get_current_network() {
    local config_file="${PSYUP_CONFIG:-$PSY_HOME/config.json}"
    if [ -f "$config_file" ]; then
        python3 -c "
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
    print(cfg.get('defaultNetwork', 'unknown'))
except Exception:
    print('unknown')
" "$config_file" 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

validate_network_in_config() {
    local config_file=$1 network=$2
    [ -f "$config_file" ] || die "config file not found: $config_file"
    command -v python3 >/dev/null 2>&1 || die "python3 is required to validate network config"
    python3 - "$config_file" "$network" <<'PY' >/dev/null
import json, sys
cfg = json.load(open(sys.argv[1]))
network = sys.argv[2]
nets = cfg.get("networks", {})
if network not in nets:
    available = ", ".join(sorted(nets.keys())) if isinstance(nets, dict) and nets else "<none>"
    print(f"invalid network '{network}' (available: {available})", file=sys.stderr)
    sys.exit(1)
PY
    [ $? -eq 0 ] || die "invalid default network '$network' for $config_file"
}
