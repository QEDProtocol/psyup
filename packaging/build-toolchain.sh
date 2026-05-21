#!/usr/bin/env bash
# Clone, build, collect, and package the real PSY toolchain.
#
# Usage:
#     bash packaging/build-toolchain.sh
#
# Environment:
#     PSY_TOOLCHAIN_VERSION   Toolchain version. Default: v0.1.0
#     VERSION                 Fallback version env var.
#     PSY_TOOLCHAIN_BRANCH    Source branch. Default: feat/shield-poseidon-bridge
#     BRANCH                  Fallback branch env var.
#     PARTH_REPO              parth-generic-v1 git URL.
#     PSY_COMPILER_REPO       psy-compiler git URL.
#     PSY_STD_DIR             Override psy-std source. Default: dist/psy-compiler/psy-std
#     PSY_TOOLCHAIN_TRIPLE    Override inferred platform triple.
#
# Output:
#     dist/psy-toolchain-v<version>-<triple>/
#     dist/psy-toolchain-v<version>-<triple>.tar.gz
#     dist/SHA256SUMS

set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
dist="$repo_root/dist"
mkdir -p "$dist"

version_input=${PSY_TOOLCHAIN_VERSION:-${VERSION:-v0.1.0}}
version_no_v=${version_input#v}
version="v${version_no_v}"

branch=${PSY_TOOLCHAIN_BRANCH:-${BRANCH:-feat/shield-poseidon-bridge}}
parth_repo=${PARTH_REPO:-git@github.com:QEDProtocol/parth-generic-v1.git}
compiler_repo=${PSY_COMPILER_REPO:-git@github.com:QEDProtocol/psy-compiler.git}

BINARIES=(psy_dev_cli psy_node_cli psy_relayer_cli psy_user_cli psy_worker_cli dargo)

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

triple=${PSY_TOOLCHAIN_TRIPLE:-$(infer_triple)}

clone_or_update() {
    local url=$1
    local dir=$2

    if [ -d "$dir/.git" ]; then
        echo "==> Updating $(basename "$dir")"
        git -C "$dir" fetch origin "$branch"
    elif [ -e "$dir" ]; then
        echo "error: $dir exists but is not a git checkout" >&2
        return 1
    else
        echo "==> Cloning $(basename "$dir")"
        git clone "$url" "$dir"
    fi

    git -C "$dir" checkout "$branch"
    git -C "$dir" pull --ff-only origin "$branch"
}

build_repo() {
    local dir=$1
    echo "==> Building $(basename "$dir")"
    ( cd "$dir" && make build )
}

find_binary() {
    local root=$1
    local name=$2
    local path

    for path in \
        "$root/target/release/$name" \
        "$root/target/debug/$name" \
        "$root/build/$name" \
        "$root/bin/$name" \
        "$root/$name"
    do
        if [ -x "$path" ]; then
            echo "$path"
            return 0
        fi
    done

    path=$(find "$root" -type f -name "$name" -perm -111 -print -quit)
    if [ -n "$path" ]; then
        echo "$path"
        return 0
    fi

    echo "error: could not find executable $name under $root" >&2
    return 1
}

copy_binary() {
    local root=$1
    local name=$2
    local src

    src=$(find_binary "$root" "$name")
    cp "$src" "$stage/bin/$name"
    chmod +x "$stage/bin/$name"
    echo "    $name <- ${src#$repo_root/}"
}

write_checksum() {
    local tarball=$1
    local name
    name=$(basename "$tarball")

    if command -v sha256sum >/dev/null 2>&1; then
        ( cd "$dist" && sha256sum "$name" ) >> "$dist/SHA256SUMS"
    else
        ( cd "$dist" && shasum -a 256 "$name" ) >> "$dist/SHA256SUMS"
    fi
}

create_tarball() {
    local tarball=$1
    local dirname=$2

    rm -f "$tarball"
    if tar --help 2>/dev/null | grep -q -- "--no-xattrs"; then
        ( cd "$dist" && COPYFILE_DISABLE=1 tar --no-xattrs -czf "$tarball" "$dirname" )
    else
        ( cd "$dist" && COPYFILE_DISABLE=1 tar --no-xattrs --no-fflags --no-acls -czf "$tarball" "$dirname" )
    fi
}

parth_dir="$dist/parth-generic-v1"
compiler_dir="$dist/psy-compiler"
psy_std_dir=${PSY_STD_DIR:-$compiler_dir/psy-std}
toolchain_dirname="psy-toolchain-${version}-${triple}"
stage="$dist/$toolchain_dirname"
tarball="$dist/${toolchain_dirname}.tar.gz"

clone_or_update "$parth_repo" "$parth_dir"
clone_or_update "$compiler_repo" "$compiler_dir"

build_repo "$parth_dir"
build_repo "$compiler_dir"

echo "==> Staging $toolchain_dirname"
rm -rf "$stage"
mkdir -p "$stage/bin" "$stage/lib"

copy_binary "$parth_dir" psy_dev_cli
copy_binary "$parth_dir" psy_node_cli
copy_binary "$parth_dir" psy_relayer_cli
copy_binary "$parth_dir" psy_user_cli
copy_binary "$parth_dir" psy_worker_cli
copy_binary "$compiler_dir" dargo

if [ ! -f "$psy_std_dir/std.psy" ]; then
    echo "error: $psy_std_dir/std.psy not found" >&2
    exit 1
fi

echo "    psy-std <- ${psy_std_dir#$repo_root/}"
cp -R "$psy_std_dir" "$stage/lib/psy-std"
rm -rf "$stage/lib/psy-std/target"

if [ -f "$repo_root/config.json" ]; then
    cp "$repo_root/config.json" "$stage/config.json"
fi

echo "==> Packaging ${tarball#$repo_root/}"
create_tarball "$tarball" "$toolchain_dirname"

tmp_sums="$dist/SHA256SUMS.tmp"
if [ -f "$dist/SHA256SUMS" ]; then
    grep -v "  $(basename "$tarball")$" "$dist/SHA256SUMS" > "$tmp_sums" || true
    mv "$tmp_sums" "$dist/SHA256SUMS"
else
    : > "$dist/SHA256SUMS"
fi
write_checksum "$tarball"

echo
echo "done:"
echo "  $stage"
echo "  $tarball"
echo "  $dist/SHA256SUMS"
