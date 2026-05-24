# psyup init — create default wallet

cmd_init() {
    local keystore_dir="$PSY_HOME/keystore"
    local keystore_file="$keystore_dir/default"

    if [ -f "$keystore_file" ]; then
        say "wallet already exists at $keystore_file"
        say ""
        say "To export your private key:"
        say "  export PSY_PRIVATE_KEY=$(psy_user_cli wallet info --keystore-path $keystore_file 2>/dev/null | grep 'private_key:' | awk '{print \$2}')"
        return 0
    fi

    say "creating wallet at $keystore_file..."
    mkdir -p "$keystore_dir"

    psy_user_cli wallet create -o "$keystore_file" || die "failed to create wallet"

    say ""
    say "wallet created"
    say "export PSY_PRIVATE_KEY=<your-hex-key>"
}
