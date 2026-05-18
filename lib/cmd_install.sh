# psyup install / update / uninstall

resolve_latest_version() {
    need curl
    local api="https://api.github.com/repos/${PSYUP_TOOLCHAIN_REPO}/releases/latest"
    local tag fallback="${PSYUP_DEFAULT_VERSION:-0.1.0}"
    tag=$(curl -fsSL "$api" 2>/dev/null | awk -F'"' '/"tag_name":/ {print $4; exit}') || tag=""
    if [ -z "$tag" ]; then
        warn "failed to resolve latest version from $api; falling back to $fallback"
        printf '%s\n' "$fallback"
        return 0
    fi
    # strip leading v
    printf '%s\n' "${tag#v}"
}

current_version() {
    settings_get active
}

install_toolchain() {
    local version=$1 triple default_network
    triple=$(detect_triple)
    default_network=${PSYUP_DEFAULT_NETWORK:-$(settings_get default_network)}
    [ -n "$default_network" ] || default_network=localhost
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

    update_settings "$version" "$default_network"

    rm -rf "$tmp"

    write_env_paths "$version" "$default_network"

    say "installed PSY toolchain $version"
}

# Rewrite managed lines in ~/.psy/env to point at files installed from the
# active toolchain. The toolchain tarball is expected to ship psy-std at
# <toolchain>/lib/psy-std/std.psy and config.json at the toolchain root.
write_env_paths() {
    local version=$1
    local default_network=$2
    local std_path="$PSY_HOME/toolchains/psy-${version}/lib/psy-std/std.psy"
    local toolchain_config="$PSY_HOME/toolchains/psy-${version}/config.json"
    local rpc_config="$PSY_HOME/config.json"
    local env_file="$PSY_HOME/env"
    local have_rpc_config=0

    [ -f "$env_file" ] || return 0

    if [ ! -f "$std_path" ]; then
        warn "psy-std not found at $std_path"
        warn "  the toolchain release should ship lib/psy-std/std.psy"
        warn "  builds will fall back to git-cloning std (slow)"
    fi

    if [ -f "$toolchain_config" ]; then
        cp "$toolchain_config" "$rpc_config"
        set_config_default_network "$rpc_config" "$default_network"
        have_rpc_config=1
    elif [ -f "$rpc_config" ]; then
        set_config_default_network "$rpc_config" "$default_network"
        have_rpc_config=1
    else
        warn "config.json not found at $toolchain_config"
        warn "  the toolchain release should ship config.json or install.sh should install $rpc_config"
        warn "  deploy will require --rpc-config or RPC_CONFIG"
    fi

    local tmpf
    tmpf=$(mktemp)
    awk -v std="$std_path" -v rpc="$rpc_config" -v have_rpc="$have_rpc_config" '
        /^# DARGO_STD_PATH=__PSYUP_MANAGED__/ { seen_std=1; print "export DARGO_STD_PATH=\"" std "\""; next }
        /^export DARGO_STD_PATH=/ { seen_std=1; print "export DARGO_STD_PATH=\"" std "\""; next }
        /^# RPC_CONFIG=__PSYUP_MANAGED__/ {
            seen_rpc=1
            if (have_rpc == 1) print "export RPC_CONFIG=\"" rpc "\""
            else print
            next
        }
        /^export RPC_CONFIG=/ {
            seen_rpc=1
            if (have_rpc == 1) print "export RPC_CONFIG=\"" rpc "\""
            else print
            next
        }
        { print }
        END {
            if (seen_std != 1) print "export DARGO_STD_PATH=\"" std "\""
            if (have_rpc == 1 && seen_rpc != 1) print "export RPC_CONFIG=\"" rpc "\""
        }
    ' "$env_file" > "$tmpf" && mv "$tmpf" "$env_file"

    say "DARGO_STD_PATH -> $std_path"
    if [ "$have_rpc_config" -eq 1 ]; then
        say "RPC_CONFIG -> $rpc_config"
    fi
}

update_settings() {
    local version=$1 default_network=$2 settings="$PSY_HOME/settings.toml"
    local tmpf

    if [ ! -f "$settings" ]; then
        cat > "$settings" <<EOF
# psyup user settings
active = "$version"
default_network = "$default_network"
EOF
        return 0
    fi

    tmpf=$(mktemp)
    awk -v v="$version" -v n="$default_network" '
        /^active[[:space:]]*=/ {
            print "active = \"" v "\""
            seen_active=1
            next
        }
        /^default_network[[:space:]]*=/ {
            print "default_network = \"" n "\""
            seen_network=1
            next
        }
        { print }
        END {
            if (seen_active != 1) print "active = \"" v "\""
            if (seen_network != 1) print "default_network = \"" n "\""
        }
    ' "$settings" > "$tmpf" && mv "$tmpf" "$settings"
}

set_config_default_network() {
    local config=$1 default_network=$2 tmpf
    tmpf=$(mktemp)
    awk -v n="$default_network" '
        function count_char(s, c,    i, total) {
            total = 0
            for (i = 1; i <= length(s); i++) {
                if (substr(s, i, 1) == c) total++
            }
            return total
        }
        function flush_prev() {
            if (prev != "") {
                print prev
                prev = ""
            }
        }
        /^[[:space:]]*"defaultNetwork"[[:space:]]*:/ {
            comma = ($0 ~ /,[[:space:]]*$/) ? "," : ""
            indent = $0
            sub(/"defaultNetwork".*$/, "", indent)
            flush_prev()
            print indent "\"defaultNetwork\": \"" n "\"" comma
            seen=1
            depth += count_char($0, "{") - count_char($0, "}")
            next
        }
        /^[[:space:]]*}[[:space:]]*$/ && seen != 1 && depth == 1 {
            if (prev != "" && prev !~ /,[[:space:]]*$/) prev = prev ","
            flush_prev()
            print "  \"defaultNetwork\": \"" n "\""
            seen=1
        }
        {
            flush_prev()
            prev = $0
            depth += count_char($0, "{") - count_char($0, "}")
        }
        END { flush_prev() }
    ' "$config" > "$tmpf" && mv "$tmpf" "$config"
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
