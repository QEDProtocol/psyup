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

    if ! psy_user_cli wallet create --output "$keystore_file"; then
        die "failed to create wallet"
    fi

    say ""
    say "✅ wallet created"
    say "export PSY_PRIVATE_KEY=<your-hex-key>"
    say ""
    say "To register on chain, run:"
    say "  psy_user_cli register-user --private-key <your-private-key> --fingerprint <fingerprint> --sign-type zk"
}
