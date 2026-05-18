# psyup build — wraps `dargo compile` in the current project.

# Find the active toolchain's bundled psy-std and export DARGO_STD_PATH so
# the compiler doesn't have to fall back to git. Duplicates ~/.psy/env so
# `psyup build` works even from a shell that hasn't sourced env.
ensure_dargo_std_path() {
    [ -n "${DARGO_STD_PATH:-}" ] && return 0

    local active std_path
    active=$(settings_get active)
    [ -n "$active" ] || return 0

    std_path="$PSY_HOME/toolchains/psy-${active}/lib/psy-std/std.psy"
    if [ -f "$std_path" ]; then
        export DARGO_STD_PATH="$std_path"
    fi
}

# Read `entry = "..."` from Dargo.toml, falling back to src/main.psy.
contract_entry_file() {
    local entry
    entry=$(awk -F'=' '
        $1 ~ /^[[:space:]]*entry[[:space:]]*$/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            gsub(/^"|"$|[[:space:]]+$/, "")
            print
            exit
        }
    ' Dargo.toml 2>/dev/null)
    if [ -n "$entry" ]; then
        printf '%s\n' "$entry"
    else
        printf 'src/main.psy\n'
    fi
}

# Find the #[contract]-annotated struct in the entry file and return
# <name>Ref. Empty output means nothing detected; caller should fall through.
detect_contract_name() {
    local entry=$1
    [ -f "$entry" ] || return 0
    # Skip blank/comment/derive/attribute lines after #[contract]; the next
    # struct's name (with optional `pub`) is our target.
    awk '
        /#\[contract\]/ { in_contract=1; next }
        in_contract && /^[[:space:]]*$/ { next }
        in_contract && /^[[:space:]]*\/\// { next }
        in_contract && /^[[:space:]]*#\[/ { next }
        in_contract && /^[[:space:]]*(pub[[:space:]]+)?struct[[:space:]]/ {
            sub(/^[[:space:]]*(pub[[:space:]]+)?struct[[:space:]]+/, "")
            sub(/[[:space:]<{].*$/, "")
            print $0 "Ref"
            exit
        }
    ' "$entry"
}

cmd_build() {
    [ -f Dargo.toml ] \
        || die "no Dargo.toml in current directory (run 'psyup new <name>' first)"

    command -v dargo >/dev/null 2>&1 \
        || die "dargo not found in PATH (run 'psyup install' first)"

    ensure_dargo_std_path

    # Auto-fill --contract-name unless the user passed one.
    local has_contract_name=0 arg
    for arg in "$@"; do
        case "$arg" in
            --contract-name|--contract-name=*) has_contract_name=1; break ;;
        esac
    done

    if [ "$has_contract_name" -eq 0 ]; then
        local entry name
        entry=$(contract_entry_file)
        name=$(detect_contract_name "$entry")
        if [ -n "$name" ]; then
            say "detected contract: $name (from $entry)"
            set -- --contract-name="$name" "$@"
        fi
    fi

    exec dargo compile "$@"
}
