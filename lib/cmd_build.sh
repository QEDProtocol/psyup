# psyup build — wraps `dargo build` in the current project.

# Find the active toolchain's bundled psy-std and export DARGO_STD_PATH so
# the compiler doesn't have to fall back to git. This duplicates ~/.psy/env
# so `psyup build` works even from a shell that hasn't sourced env.
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

cmd_build() {
    [ -f Dargo.toml ] \
        || die "no Dargo.toml in current directory (run 'psyup new <name>' first)"

    command -v dargo >/dev/null 2>&1 \
        || die "dargo not found in PATH (run 'psyup install' first)"

    ensure_dargo_std_path
    exec dargo build "$@"
}
