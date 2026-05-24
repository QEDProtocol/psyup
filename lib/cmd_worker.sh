# psyup worker — run the proof miner with auto-resolved user identity

has_flag() {
    local needle=$1; shift
    for a in "$@"; do
        case "$a" in
            "$needle"|"$needle"=*) return 0 ;;
        esac
    done
    return 1
}

get_worker_api_urls() {
    local config_file=$1
    python3 - "$config_file" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
networks = cfg.get("networks", {})
name = cfg.get("defaultNetwork")
if not name or name not in networks:
    sys.exit(0)
net = networks[name]
for entry in net.get("coordinator_configs", []):
    urls = entry.get("rpc_url") or []
    if isinstance(urls, str):
        urls = [urls]
    for url in urls:
        if url:
            print(f"C\t{url}")
for entry in net.get("realm_configs", []):
    urls = entry.get("rpc_url") or []
    if isinstance(urls, str):
        urls = [urls]
    for url in urls:
        if url:
            print(f"R\t{url}")
PY
}

cmd_worker() {
    local keystore_dir="$PSY_HOME/keystore"
    local keystore_file="$keystore_dir/default"
    local rpc_config="$PSY_HOME/config.json"
    local user_id=""
    local has_keystore=0
    local has_private_key=0
    local private_key=""

    if [ -f "$keystore_file" ]; then
        has_keystore=1
    fi

    private_key="${PRIVATE_KEY:-}"
    if [ -n "$private_key" ]; then
        has_private_key=1
    fi

    if [ "$has_keystore" -eq 0 ] && [ "$has_private_key" -eq 0 ]; then
        die "no wallet found. Run 'psyup init' first to create a wallet, or set PRIVATE_KEY."
    fi

    local pub_key=""
    local wallet_password=""

    if [ "$has_private_key" -eq 1 ]; then
        say "using PRIVATE_KEY for identity"
        local info_out info_rc=0
        info_out=$(psy_user_cli wallet info --private-key "$private_key" 2>&1) || info_rc=$?
        if [ "$info_rc" -ne 0 ]; then
            printf '%s\n' "$info_out" >&2
            die "failed to derive public key from PRIVATE_KEY"
        fi
        pub_key=$(printf '%s\n' "$info_out" | awk '/public_key_param:/ {print $2; exit}')
        [ -n "$pub_key" ] || die "wallet info did not contain public_key_param (private key invalid?)"
    else
        if [ -z "${WALLET_PASSWORD:-}" ]; then
            printf 'Enter keystore password: ' >&2
            IFS= read -rs WALLET_PASSWORD
            printf '\n' >&2
        fi
        wallet_password="$WALLET_PASSWORD"
        unset WALLET_PASSWORD

        local info_out info_rc=0
        info_out=$(psy_user_cli wallet info --keystore-path "$keystore_file" --wallet-password "$wallet_password" 2>&1) || info_rc=$?
        if [ "$info_rc" -ne 0 ]; then
            printf '%s\n' "$info_out" >&2
            die "failed to read wallet info; check keystore password"
        fi
        pub_key=$(printf '%s\n' "$info_out" | awk '/public_key_param:/ {print $2; exit}')
        [ -n "$pub_key" ] || die "wallet info did not contain public_key_param (corrupt keystore?)"
    fi

    say "resolving user_id..."
    local id_out id_rc=0
    id_out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$pub_key" 2>&1) || id_rc=$?
    if [ "$id_rc" -ne 0 ]; then
        printf '%s\n' "$id_out" >&2
        case "$id_out" in
            *"no user ids found"*)
                die "no user_id found for this wallet on $(get_current_network); run 'psyup init' to register"
                ;;
            *"Connection error"*|*"error sending request"*|*"timed out"*|*"dns error"*)
                die "get-user-id failed; is RPC reachable? (network: $(get_current_network))"
                ;;
            *)
                die "get-user-id failed on $(get_current_network)"
                ;;
        esac
    fi
    user_id=$(printf '%s\n' "$id_out" | awk '/user_id:/ {print $2; exit}')
    if [ -z "$user_id" ]; then
        die "failed to resolve user_id; is this wallet registered on $(get_current_network)? Run 'psyup init' to register."
    fi

    say "✅ user_id: $user_id (network: $(get_current_network))"
    say ""
    say "starting worker..."
    say ""

    local worker_args=()
    if [ "$has_private_key" -eq 1 ]; then
        worker_args+=("--private-key" "$private_key")
    else
        worker_args+=("--keystore-path" "$keystore_file" "--wallet-password" "$wallet_password")
    fi
    worker_args+=("--user" "$user_id")

    # Worker network enum is NOT the same namespace as config.json defaultNetwork.
    # Current supported mapping: localhost -> local-devnet.
    if ! has_flag --network "$@"; then
        case "$(get_current_network)" in
            localhost)
                worker_args+=("--network" "local-devnet")
                ;;
            *)
                wallet_password=""
                die "psyup worker currently only supports defaultNetwork=localhost (local devnet); got '$(get_current_network)'"
                ;;
        esac
    fi

    # Map shared ~/.psy/config.json network config into worker-specific API URL args
    # unless the user already passed their own explicit worker API URLs.
    local mapped_urls="" kind="" url="" have_coord=0 have_realm=0
    if ! has_flag --coordinator-api-url "$@" || ! has_flag --realm-api-url "$@"; then
        mapped_urls=$(get_worker_api_urls "$rpc_config" 2>/dev/null) || mapped_urls=""
        while IFS=$'\t' read -r kind url; do
            [ -n "$kind" ] || continue
            case "$kind" in
                C)
                    if ! has_flag --coordinator-api-url "$@"; then
                        worker_args+=("--coordinator-api-url" "$url")
                        have_coord=1
                    fi
                    ;;
                R)
                    if ! has_flag --realm-api-url "$@"; then
                        worker_args+=("--realm-api-url" "$url")
                        have_realm=1
                    fi
                    ;;
            esac
        done <<EOF
$mapped_urls
EOF
    fi

    if ! has_flag --coordinator-api-url "$@" && [ "$have_coord" -ne 1 ]; then
        warn "no coordinator API URLs found in $rpc_config for network $(get_current_network)"
    fi
    if ! has_flag --realm-api-url "$@" && [ "$have_realm" -ne 1 ]; then
        warn "no realm API URLs found in $rpc_config for network $(get_current_network)"
    fi

    worker_args+=("$@")

    local worker_rc=0
    psy_worker_cli worker "${worker_args[@]}" || worker_rc=$?
    wallet_password=""
    return "$worker_rc"
}
