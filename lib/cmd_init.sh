# psyup init — create default wallet and register on chain

# Read wallet identifiers from a wallet (keystore + password).
# Prints two TAB-separated fields on stdout: public_key_hash<TAB>public_key_param
# Returns non-zero on failure with diagnostics on stderr.
_read_wallet_ids_from_keystore() {
    local keystore_file=$1 password=$2
    local out rc=0
    out=$(psy_user_cli wallet info --keystore-path "$keystore_file" --wallet-password "$password" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$out" >&2
        return 1
    fi
    local pkh pkp
    pkh=$(printf '%s\n' "$out" | awk '/public_key_hash:/ {print $2; exit}')
    pkp=$(printf '%s\n' "$out" | awk '/public_key_param:/ {print $2; exit}')
    if [ -z "$pkh" ] || [ -z "$pkp" ]; then
        printf '%s\n' "$out" >&2
        return 1
    fi
    printf '%s\t%s\n' "$pkh" "$pkp"
}

# Poll until a registered wallet becomes readable via get-user-id.
# Prints the user_id on stdout and returns 0 when visible.
_wait_for_user_id() {
    local rpc_config=$1 public_key_hash=$2 attempts=${3:-30}
    local i out rc user_id

    say "waiting for user_id to become visible on $(get_current_network)..."
    for i in $(seq 1 "$attempts"); do
        out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$public_key_hash" 2>&1) || rc=$?
        rc=${rc:-0}
        if [ "$rc" -eq 0 ]; then
            user_id=$(printf '%s\n' "$out" | awk '/user_id:/ {print $2; exit}')
            if [ -n "$user_id" ]; then
                printf '%s\n' "$user_id"
                return 0
            fi
        elif ! printf '%s\n' "$out" | grep -q 'no user ids found'; then
            printf '%s\n' "$out" >&2
            return 1
        fi
        sleep 1
        rc=0
    done
    return 1
}

cmd_init() {
    local keystore_dir="$PSY_HOME/keystore"
    local keystore_file="$keystore_dir/default"
    local rpc_config="$PSY_HOME/config.json"

    # --- Case 1: keystore already exists ---
    if [ -f "$keystore_file" ]; then
        say "wallet already exists at $keystore_file"
        say ""

        printf 'Enter keystore password: ' >&2
        IFS= read -rs WALLET_PASSWORD
        printf '\n' >&2
        local password="$WALLET_PASSWORD"
        unset WALLET_PASSWORD

        local wallet_ids public_key_hash pub_key
        wallet_ids=$(_read_wallet_ids_from_keystore "$keystore_file" "$password") \
            || die "failed to read wallet info; check keystore password"
        public_key_hash=$(printf '%s\n' "$wallet_ids" | cut -f1)
        pub_key=$(printf '%s\n' "$wallet_ids" | cut -f2)

        say "public_key_param: $pub_key"
        say ""

        local id_out id_rc=0
        id_out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$public_key_hash" 2>&1) || id_rc=$?
        local user_id=""
        if [ "$id_rc" -ne 0 ]; then
            case "$id_out" in
                *"no user ids found"*)
                    user_id=""
                    ;;
                *)
                    printf '%s\n' "$id_out" >&2
                    password=""
                    die "get-user-id failed; is RPC reachable? (network: $(get_current_network))"
                    ;;
            esac
        else
            user_id=$(printf '%s\n' "$id_out" | awk '/user_id:/ {print $2; exit}')
        fi

        if [ -n "$user_id" ]; then
            say "✅ user already registered (user_id: $user_id, network: $(get_current_network))"
            password=""
            return 0
        fi

        say "user not registered on the current network ($(get_current_network))"
        say "registering on chain..."

        local rc=0
        RPC_CONFIG="$rpc_config" psy_user_cli register-user \
            --keystore-path "$keystore_file" \
            --wallet-password "$password" \
            --sign-type zk 2>&1 || rc=$?
        password=""

        if [ "$rc" -eq 0 ]; then
            local registered_user_id=""
            registered_user_id=$(_wait_for_user_id "$rpc_config" "$public_key_hash" 30) || {
                say "⚠️ registration submitted, but user_id is not visible yet"
                say "  Retry shortly: psy_user_cli get-user-id --pub-key $public_key_hash"
                return 1
            }
            say "✅ registered on chain"
            say "✅ user_id: $registered_user_id"
            return 0
        else
            say "⚠️ registration failed"
            say "  Manual: psy_user_cli register-user --keystore-path $keystore_file --sign-type zk"
            return "$rc"
        fi
    fi

    # --- Case 2: create new keystore ---
    say "creating wallet at $keystore_file..."
    mkdir -p "$keystore_dir"

    printf 'Enter password for wallet: ' >&2
    IFS= read -rs WALLET_PASSWORD
    printf '\n' >&2
    local password="$WALLET_PASSWORD"
    unset WALLET_PASSWORD

    local rc=0
    psy_user_cli wallet create --output "$keystore_file" --password "$password" 2>&1 || rc=$?
    if [ "$rc" -ne 0 ]; then
        password=""
        die "failed to create wallet"
    fi

    local wallet_ids public_key_hash pub_key
    wallet_ids=$(_read_wallet_ids_from_keystore "$keystore_file" "$password") \
        || { password=""; die "wallet created but failed to read its info"; }
    public_key_hash=$(printf '%s\n' "$wallet_ids" | cut -f1)
    pub_key=$(printf '%s\n' "$wallet_ids" | cut -f2)

    say ""
    say "✅ wallet created"
    say "keystore: $keystore_file"
    say "public_key_param: $pub_key"
    say ""

    say "checking if user is already registered..."
    local id_out id_rc=0
    id_out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$public_key_hash" 2>&1) || id_rc=$?
    local user_id=""
    if [ "$id_rc" -ne 0 ]; then
        case "$id_out" in
            *"no user ids found"*)
                user_id=""
                ;;
            *)
                printf '%s\n' "$id_out" >&2
                password=""
                die "get-user-id failed; is RPC reachable? (network: $(get_current_network))"
                ;;
        esac
    else
        user_id=$(printf '%s\n' "$id_out" | awk '/user_id:/ {print $2; exit}')
    fi
    if [ -n "$user_id" ]; then
        say "✅ user already registered (user_id: $user_id)"
        password=""
        return 0
    fi

    say ""
    say "registering on chain..."
    local rc2=0
    RPC_CONFIG="$rpc_config" psy_user_cli register-user \
        --keystore-path "$keystore_file" \
        --wallet-password "$password" \
        --sign-type zk 2>&1 || rc2=$?
    password=""

    if [ "$rc2" -eq 0 ]; then
        local registered_user_id=""
        registered_user_id=$(_wait_for_user_id "$rpc_config" "$public_key_hash" 30) || {
            say "⚠️ registration submitted, but user_id is not visible yet"
            say "  Retry shortly: psy_user_cli get-user-id --pub-key $public_key_hash"
            return 1
        }
        say "✅ registered on chain"
        say "✅ user_id: $registered_user_id"
        return 0
    else
        say "⚠️ registration failed"
        say "  To register manually, run:"
        say "  psy_user_cli register-user --keystore-path $keystore_file --sign-type zk"
        return "$rc2"
    fi
}
