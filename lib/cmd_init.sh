# psyup init — create default wallet and register on chain

# Read pub_key from a wallet (keystore + password, or private key).
# Echoes pub_key on stdout. Returns non-zero on failure with diagnostics on stderr.
_read_pub_key_from_keystore() {
    local keystore_file=$1 password=$2
    local out rc=0
    out=$(psy_user_cli wallet info --keystore-path "$keystore_file" --wallet-password "$password" 2>&1) || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$out" >&2
        return 1
    fi
    local pk
    pk=$(printf '%s\n' "$out" | awk '/public_key_param:/ {print $2; exit}')
    if [ -z "$pk" ]; then
        printf '%s\n' "$out" >&2
        return 1
    fi
    printf '%s\n' "$pk"
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

        local pub_key
        pub_key=$(_read_pub_key_from_keystore "$keystore_file" "$password") \
            || die "failed to read wallet info; check keystore password"

        say "public_key_param: $pub_key"
        say ""

        local id_out id_rc=0
        id_out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$pub_key" 2>&1) || id_rc=$?
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
            say "✅ registered on chain"
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

    local pub_key
    pub_key=$(_read_pub_key_from_keystore "$keystore_file" "$password") \
        || { password=""; die "wallet created but failed to read its info"; }

    say ""
    say "✅ wallet created"
    say "keystore: $keystore_file"
    say "public_key_param: $pub_key"
    say ""

    say "checking if user is already registered..."
    local id_out id_rc=0
    id_out=$(RPC_CONFIG="$rpc_config" psy_user_cli get-user-id --pub-key "$pub_key" 2>&1) || id_rc=$?
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
        say "✅ registered on chain"
        return 0
    else
        say "⚠️ registration failed"
        say "  To register manually, run:"
        say "  psy_user_cli register-user --keystore-path $keystore_file --sign-type zk"
        return "$rc2"
    fi
}
