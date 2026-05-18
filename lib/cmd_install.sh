# psyup install / update / uninstall

resolve_latest_version() {
    need curl
    local api="https://api.github.com/repos/${PSYUP_TOOLCHAIN_REPO}/releases/latest"
    local tag
    tag=$(curl -fsSL "$api" | awk -F'"' '/"tag_name":/ {print $4; exit}')
    [ -n "$tag" ] || die "failed to resolve latest version from $api"
    # strip leading v
    printf '%s\n' "${tag#v}"
}

current_version() {
    settings_get active
}

install_toolchain() {
    local version=$1 triple
    triple=$(detect_triple)
    # PSYUP_RELEASE_URL overrides the release source (any URL curl supports:
    # https://, file://, etc). Useful for local dist/ testing or mirrors.
    local base="${PSYUP_RELEASE_URL:-https://github.com/${PSYUP_TOOLCHAIN_REPO}/releases/download/v${version}}"
    local tarball="psy-toolchain-v${version}-${triple}.tar.gz"
    local sums="SHA256SUMS"
    local dest="$PSY_HOME/toolchains/psy-${version}"
    local tmp
    tmp=$(mktemp -d)

    say "downloading $tarball"
    curl -fsSL "$base/$tarball" -o "$tmp/$tarball" \
        || die "failed to download $base/$tarball"
    curl -fsSL "$base/$sums" -o "$tmp/$sums" \
        || die "failed to download $base/$sums"

    local expected
    expected=$(awk -v f="$tarball" '$2 == f || $2 == "*"f {print $1; exit}' "$tmp/$sums")
    [ -n "$expected" ] || die "no checksum entry for $tarball in $sums"
    sha256_verify "$tmp/$tarball" "$expected"

    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xzf "$tmp/$tarball" -C "$dest" --strip-components=1 \
        || die "failed to extract $tarball"

    # Symlink binaries into ~/.psy/bin
    mkdir -p "$PSY_HOME/bin"
    local b
    for b in "$dest"/bin/*; do
        [ -e "$b" ] || continue
        ln -sf "$b" "$PSY_HOME/bin/$(basename "$b")"
    done

    # Update active version (rewrite settings.toml's `active = "..."`).
    local s="$PSY_HOME/settings.toml"
    if [ -f "$s" ] && grep -q '^active[[:space:]]*=' "$s"; then
        # portable in-place edit
        local tmpf
        tmpf=$(mktemp)
        awk -v v="$version" '
            /^active[[:space:]]*=/ { print "active = \"" v "\""; next }
            { print }
        ' "$s" > "$tmpf" && mv "$tmpf" "$s"
    else
        printf 'active = "%s"\n' "$version" >> "$s"
    fi

    rm -rf "$tmp"

    write_dargo_std_path "$version"

    say "installed PSY toolchain $version"
}

# Rewrite the DARGO_STD_PATH line in ~/.psy/env to point at the given
# toolchain's bundled std.psy. The toolchain tarball is expected to ship
# psy-std at <toolchain>/lib/psy-std/std.psy (see README).
write_dargo_std_path() {
    local version=$1
    local std_path="$PSY_HOME/toolchains/psy-${version}/lib/psy-std/std.psy"
    local env_file="$PSY_HOME/env"

    [ -f "$env_file" ] || return 0

    if [ ! -f "$std_path" ]; then
        warn "psy-std not found at $std_path"
        warn "  the toolchain release should ship lib/psy-std/std.psy"
        warn "  builds will fall back to git-cloning std (slow)"
        return 0
    fi

    local tmpf
    tmpf=$(mktemp)
    awk -v p="$std_path" '
        /^# DARGO_STD_PATH=__PSYUP_MANAGED__/ { print "export DARGO_STD_PATH=\"" p "\""; next }
        /^export DARGO_STD_PATH=/ { print "export DARGO_STD_PATH=\"" p "\""; next }
        { print }
    ' "$env_file" > "$tmpf" && mv "$tmpf" "$env_file"

    say "DARGO_STD_PATH -> $std_path"
}

cmd_install() {
    local version=${1:-}
    if [ -z "$version" ] || [ "$version" = "latest" ]; then
        version=$(resolve_latest_version)
    fi
    install_toolchain "$version"
}

cmd_update() {
    local latest current
    latest=$(resolve_latest_version)
    current=$(current_version)
    if [ "$current" = "$latest" ]; then
        say "already up to date ($current)"
        return 0
    fi
    say "updating $current -> $latest"
    install_toolchain "$latest"
}

cmd_uninstall() {
    printf 'psyup: this will remove %s. continue? [y/N] ' "$PSY_HOME"
    local reply
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) say "aborted"; return 0 ;;
    esac
    rm -rf "$PSY_HOME"
    say "removed $PSY_HOME"
    say "note: you may want to remove the 'source ~/.psy/env' line from your shell rc"
}
