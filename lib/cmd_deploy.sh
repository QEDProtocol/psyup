# psyup deploy — wraps `psy_user_cli deploy-contract` for the current project.
#
# Pass-through model: most flags go straight to psy_user_cli. We only auto-
# fill --rpc-config from settings.toml when the user didn't supply one.
#
# Required by psy_user_cli deploy-contract (set on CLI or via env):
#     --private-key <hex>      | PRIVATE_KEY
#     --contract-path <file>   | CONTRACT_PATH  (e.g. ./target/<name>.json)
#     --rpc-config <file>      | RPC_CONFIG     (defaults from settings.toml)
#     --is-deploy              (auto-added)

cmd_deploy() {
    [ -f Dargo.toml ] || die "no Dargo.toml in current directory"
    command -v psy_user_cli >/dev/null 2>&1 \
        || die "psy_user_cli not found in PATH (run 'psyup install' first)"

    local has_rpc_config=0
    local arg
    for arg in "$@"; do
        case "$arg" in
            --rpc-config|--rpc-config=*) has_rpc_config=1 ;;
        esac
    done

    if [ "$has_rpc_config" -eq 0 ] && [ -z "${RPC_CONFIG:-}" ]; then
        local network rpc_config
        network=$(settings_get default_network)
        [ -n "$network" ] || network=local
        rpc_config=$(awk -v n="$network" '
            $0 ~ "^\\[networks\\." n "\\]" { in_section=1; next }
            /^\[/ { in_section=0 }
            in_section && $1 == "rpc_config" && $2 == "=" {
                sub(/^[^=]*=[[:space:]]*/, "")
                gsub(/^"|"$/, "")
                print
                exit
            }
        ' "$PSY_HOME/settings.toml" 2>/dev/null)

        if [ -n "$rpc_config" ]; then
            say "using rpc_config from settings.toml ($network): $rpc_config"
            set -- --rpc-config "$rpc_config" "$@"
        fi
    fi

    exec psy_user_cli deploy-contract --is-deploy "$@"
}
