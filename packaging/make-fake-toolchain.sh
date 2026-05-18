#!/usr/bin/env bash
# Build a fake PSY toolchain release for smoke tests.
#
# Usage:
#     packaging/make-fake-toolchain.sh <version>
#
# Environment:
#     PSYUP_FAKE_TOOLCHAIN_DIR   Output directory. Defaults to a new tmp dir.
#     PSY_TOOLCHAIN_TRIPLE       Override inferred platform triple.
#
# The script prints the release directory path on stdout. It intentionally does
# not write to repo-root dist/.

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
version_input=${1:-0.1.0}
version_no_v=${version_input#v}
version="v${version_no_v}"

infer_triple() {
    local arch os
    arch=$(uname -m)
    os=$(uname -s)

    case "$arch" in
        arm64|aarch64) arch=aarch64 ;;
        x86_64|amd64) arch=x86_64 ;;
        *) echo "unsupported architecture: $arch" >&2; return 1 ;;
    esac

    case "$os" in
        Darwin) echo "${arch}-apple-darwin" ;;
        Linux) echo "${arch}-unknown-linux-gnu" ;;
        *) echo "unsupported OS: $os" >&2; return 1 ;;
    esac
}

write_checksum() {
    local dir=$1 name=$2

    if command -v sha256sum >/dev/null 2>&1; then
        ( cd "$dir" && sha256sum "$name" ) >> "$dir/SHA256SUMS"
    else
        ( cd "$dir" && shasum -a 256 "$name" ) >> "$dir/SHA256SUMS"
    fi
}

triple=${PSY_TOOLCHAIN_TRIPLE:-$(infer_triple)}
release_dir=${PSYUP_FAKE_TOOLCHAIN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/psyup-fake-release.XXXXXX")}
toolchain_dirname="psy-toolchain-${version}-${triple}"
stage="$release_dir/$toolchain_dirname"
tarball_name="${toolchain_dirname}.tar.gz"
tarball="$release_dir/$tarball_name"

mkdir -p "$stage/bin" "$stage/lib/psy-std"

for bin in dargo psy_user_cli psy_worker_cli psy_node_cli psy_dev_cli psy_relayer_cli; do
    cat > "$stage/bin/$bin" <<EOF
#!/usr/bin/env bash
echo "$bin ${version_no_v}"
EOF
    chmod +x "$stage/bin/$bin"
done

cat > "$stage/lib/psy-std/std.psy" <<'EOF'
// fake psy std
EOF

if [ -f "$repo_root/config.json" ]; then
    cp "$repo_root/config.json" "$stage/config.json"
else
    cat > "$stage/config.json" <<'EOF'
{
  "defaultNetwork": "localhost"
}
EOF
fi

rm -f "$tarball"
( cd "$release_dir" && COPYFILE_DISABLE=1 tar -czf "$tarball_name" "$toolchain_dirname" )

tmp_sums="$release_dir/SHA256SUMS.tmp"
if [ -f "$release_dir/SHA256SUMS" ]; then
    grep -v "  $tarball_name$" "$release_dir/SHA256SUMS" > "$tmp_sums" || true
    mv "$tmp_sums" "$release_dir/SHA256SUMS"
else
    : > "$release_dir/SHA256SUMS"
fi
write_checksum "$release_dir" "$tarball_name"

printf '%s\n' "$release_dir"
