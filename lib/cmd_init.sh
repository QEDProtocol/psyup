# psyup init — create default wallet and register on chain

# Read a wallet's public_key_hash from its keystore via `wallet info`, using the
# structured WalletInfoResult (--result-file). Prints the public_key_hash on
# stdout and returns non-zero on failure. No private keys are handled.
_read_wallet_public_key_hash() {
    local keystore_file=$1 password=$2 res rc pkh
    res=$(mktemp)
    # Discard stdout (human logs incl. the private_key line); read the key from $res.
    psy_user_cli --result-file "$res" wallet info \
        --keystore-path "$keystore_file" --wallet-password "$password" >/dev/null || rc=$?
    if [ "${rc:-0}" -ne 0 ]; then
        rm -f "$res"
        return 1
    fi
    pkh=$(result_get "$res" public_key_hash)
    rm -f "$res"
    [ -n "$pkh" ] || return 1
    printf '%s\n' "$pkh"
}

# Submit a register-user request for a keystore. Prints "<status>\t<user_id>"
# (user_id empty unless already registered) and returns the psy_user_cli exit
# status. "pending" means the registration was submitted but no user_id yet.
_register_user() {
    local keystore_file=$1 password=$2 res rc status user_id
    res=$(mktemp)
    psy_user_cli --result-file "$res" register-user \
        --keystore-path "$keystore_file" --wallet-password "$password" --sign-type zk >/dev/null || rc=$?
    rc=${rc:-0}
    if [ "$rc" -eq 0 ]; then
        status=$(result_get "$res" status)
        user_id=$(result_get "$res" user_id)
    fi
    rm -f "$res"
    printf '%s\t%s\n' "${status:-}" "${user_id:-}"
    return "$rc"
}

# Poll until a registered wallet becomes visible via get-user-id. Prints the
# user_id on stdout and returns 0 once status=registered.
_wait_for_user_id() {
    local rpc_config=$1 public_key_hash=$2 attempts=${3:-30}
    local i line rc status user_id

    say "waiting for user_id to become visible on $(get_current_network)..."
    for i in $(seq 1 "$attempts"); do
        line=$(query_user_id "$rpc_config" "$public_key_hash") || rc=$?
        rc=${rc:-0}
        [ "$rc" -eq 0 ] || return 1   # real RPC/transport error, stop waiting
        status=${line%%$'\t'*}
        if [ "$status" = "registered" ]; then
            user_id=${line#*$'\t'}
            printf '%s\n' "$user_id"
            return 0
        fi
        rc=0
        sleep 1
    done
    return 1
}

cmd_init() {
    require_structured_results

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

        local public_key_hash
        public_key_hash=$(_read_wallet_public_key_hash "$keystore_file" "$password") \
            || die "failed to read wallet info; check keystore password"

        local line rc=0 status user_id=""
        line=$(query_user_id "$rpc_config" "$public_key_hash") || rc=$?
        if [ "$rc" -ne 0 ]; then
            password=""
            die "get-user-id failed; is RPC reachable? (network: $(get_current_network))"
        fi
        status=${line%%$'\t'*}
        user_id=${line#*$'\t'}
        if [ "$status" = "registered" ] && [ -n "$user_id" ]; then
            say "✅ user already registered (user_id: $user_id, network: $(get_current_network))"
            password=""
            return 0
        fi

        say "user not registered on the current network ($(get_current_network))"
        say "registering on chain..."

        local rline rrc=0 rstatus ruser_id
        rline=$(_register_user "$keystore_file" "$password") || rrc=$?
        password=""

        if [ "$rrc" -eq 0 ]; then
            rstatus=${rline%%$'\t'*}
            ruser_id=${rline#*$'\t'}
            if [ "$rstatus" = "registered" ] && [ -n "$ruser_id" ]; then
                say "✅ registered on chain"
                say "✅ user_id: $ruser_id"
                return 0
            fi
            # pending: registration submitted, poll until the user_id is visible.
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
            return "$rrc"
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

    # wallet create writes the WalletCreateResult (with public_key_hash), so we
    # read the key straight from the result instead of a second `wallet info`.
    local rc=0 res public_key_hash
    res=$(mktemp)
    psy_user_cli --result-file "$res" wallet create --output "$keystore_file" --password "$password" >/dev/null || rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -f "$res"
        password=""
        die "failed to create wallet"
    fi
    public_key_hash=$(result_get "$res" public_key_hash)
    rm -f "$res"
    [ -n "$public_key_hash" ] || { password=""; die "wallet created but result missing public_key_hash"; }

    say ""
    say "✅ wallet created"
    say "keystore: $keystore_file"

    say "checking if user is already registered..."
    local line qrc=0 status user_id=""
    line=$(query_user_id "$rpc_config" "$public_key_hash") || qrc=$?
    if [ "$qrc" -ne 0 ]; then
        password=""
        die "get-user-id failed; is RPC reachable? (network: $(get_current_network))"
    fi
    status=${line%%$'\t'*}
    user_id=${line#*$'\t'}
    if [ "$status" = "registered" ] && [ -n "$user_id" ]; then
        say "✅ user already registered (user_id: $user_id)"
        password=""
        return 0
    fi

    say ""
    say "registering on chain..."
    local rline rrc2=0 rstatus ruser_id
    rline=$(_register_user "$keystore_file" "$password") || rrc2=$?
    password=""

    if [ "$rrc2" -eq 0 ]; then
        rstatus=${rline%%$'\t'*}
        ruser_id=${rline#*$'\t'}
        if [ "$rstatus" = "registered" ] && [ -n "$ruser_id" ]; then
            say "✅ registered on chain"
            say "✅ user_id: $ruser_id"
            return 0
        fi
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
        return "$rrc2"
    fi
}
