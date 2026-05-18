# Shared helpers for psyup. Sourced, not executed.

PSY_HOME="${PSY_HOME:-$HOME/.psy}"
PSYUP_TOOLCHAIN_REPO="${PSYUP_TOOLCHAIN_REPO:-QEDProtocol/psyup}"
PSYUP_BOILERPLATE_REPO="${PSYUP_BOILERPLATE_REPO:-QEDProtocol/psy-template}"
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
