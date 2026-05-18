# psyup deploy — wraps `psy_user_cli deploy-contract` for the current project.
#
# Pass-through model: most flags go straight to psy_user_cli. If RPC_CONFIG is
# not already set, use the config.json installed into PSY_HOME.
#
# Required by psy_user_cli deploy-contract (set on CLI or via env):
#     --private-key <hex>      | PRIVATE_KEY
#     --contract-path <file>   | CONTRACT_PATH  (e.g. ./target/<name>.json)
#     --rpc-config <file>      | RPC_CONFIG     (defaults to ~/.psy/config.json)
#     --is-deploy              (auto-added)

cmd_deploy() {
    [ -f Dargo.toml ] || die "no Dargo.toml in current directory"
    command -v psy_user_cli >/dev/null 2>&1 \
        || die "psy_user_cli not found in PATH (run 'psyup install' first)"

    if [ -z "${RPC_CONFIG:-}" ] && [ -f "$PSY_HOME/config.json" ]; then
        export RPC_CONFIG="$PSY_HOME/config.json"
    fi

    exec psy_user_cli deploy-contract --is-deploy "$@"
}
