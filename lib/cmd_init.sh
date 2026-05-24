# psyup init — create default wallet and register on chain

cmd_init() {
    local keystore_dir="$PSY_HOME/keystore"
    local keystore_file="$keystore_dir/default"

    if [ -f "$keystore_file" ]; then
        say "wallet already exists at $keystore_file"
        say ""
        local pub_key
        pub_key=$(psy_user_cli wallet info --keystore-path "$keystore_file" 2>/dev/null | grep 'public_key_param:' | awk '{print $2}') || true
        if [ -n "$pub_key" ]; then
            say "public_key_param: $pub_key"
            say ""
            say "To register on chain, run:"
            say "  psy_user_cli register-user --private-key <your-private-key> --fingerprint <fingerprint> --sign-type zk"
        fi
        return 0
    fi

    say "creating wallet at $keystore_file..."
    mkdir -p "$keystore_dir"

    # Prompt for password
    printf 'Enter password for wallet: ' >&2
    IFS= read -rs WALLET_PASSWORD
    printf '\n' >&2

    local rc=0
    psy_user_cli wallet create --output "$keystore_file" --password "$WALLET_PASSWORD" 2>&1 || rc=$?
    unset WALLET_PASSWORD
    if [ "$rc" -ne 0 ]; then
        die "failed to create wallet"
    fi

    # Extract info
    local fingerprint
    fingerprint=$(psy_user_cli wallet info --keystore-path "$keystore_file" 2>/dev/null | grep 'fingerprint:' | awk '{print $2}') || true

    say ""
    say "✅ wallet created"
    say "export PSY_PRIVATE_KEY=<your-hex-key>"

    # Auto-register on chain
    if [ -n "$fingerprint" ]; then
        say ""
        say "registering on chain..."
        local rc2=0
        psy_user_cli register-user --fingerprint "$fingerprint" --sign-type zk 2>&1 || rc2=$?
        if [ "$rc2" -eq 0 ]; then
            say "✅ registered on chain"
        else
            say "⚠️ registration failed (user may already be registered)"
            say "  To register manually, run:"
            say "  psy_user_cli register-user --private-key <your-private-key> --fingerprint <fingerprint> --sign-type zk"
        fi
    fi
}
