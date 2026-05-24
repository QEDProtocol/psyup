# psyup

One-shot installer + project scaffolder for the PSY smart-contract toolchain.
Inspired by `rustup` / `foundryup`.

## End-to-end quickstart

```sh
# 1. Install psyup itself (pins the network to sepolia).
curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/feat/parth-generic-v1/install.sh \
  | PSYUP_DEFAULT_NETWORK=sepolia sh
# (no need to source — install.sh auto-writes your shell rc)

# 2. Pull the PSY toolchain (dargo + psy_user_cli + ...) for your platform.
psyup install

# 3. Scaffold a new project from the dapp template.
psyup new token-app

# 4. Compile the contract.
cd token-app/contract && psyup build

# 5. Deploy.
export PRIVATE_KEY=<your-hex-key>
psyup deploy
# → ✓ contract_uuid: …  ✓ contract_id: 7
# (written to ./.psy-deploy)

# 6. Launch the dApp frontend.
cd ../                                  # back to token-app/
pnpm install                            # or npm install
echo "VITE_PSY_CONTRACT_ID=$(jq -r .contract_id contract/.psy-deploy)" > .env.local
pnpm dev                                # http://localhost:5173
```

Open the page, [psy-wallet](https://app-stg.psy-protocol.xyz/wallet) (browser extension),
connect, then mint / transfer / claim. No manual cloning, no source builds,
no chasing dependencies.

## Commands

| Command | What it does |
|---|---|
| `psyup install [version]` | Download the PSY toolchain release for your platform, verify SHA256, symlink into `~/.psy/bin`. Defaults to `latest`. |
| `psyup update` | Re-resolve `latest` and reinstall if newer. |
| `psyup uninstall` | Remove `~/.psy` (asks first). |
| `psyup new <name> [--template <key\|owner/repo\|url>[#subdir]]` | Download a template tarball, rewrite project name in `Dargo.toml` / `package.json`, `git init`. Default template = `dapp`. |
| `psyup build [args...]` | `dargo compile` plus `dargo generate-abi -c <package>.abi`; auto-detects `--contract-name` from `#[contract]` struct for compilation. |
| `psyup deploy [args...]` | `psy_user_cli deploy-contract --is-deploy`. Auto-fills `--rpc-config`, `--contract-path`, and `--abi-path` when ABI output exists and `psy_user_cli` supports it. Polls service for numeric `contract_id` and saves to `.psy-deploy`. |

## Layout

```
~/.psy/
├── bin/            # psyup + symlinks to active toolchain
├── toolchains/     # versioned: psy-<ver>/{bin/, lib/psy-std/, config.json}
├── lib/            # psyup's own bash modules (installed by install.sh)
├── templates/      # cache (reserved, not used yet)
├── env             # source this to add ~/.psy/bin to PATH + set DARGO_STD_PATH + RPC_CONFIG
├── config.json     # RPC network config consumed by psy_user_cli (--rpc-config)
└── settings.toml   # active version, default network
```

## Repository contract

### Toolchain release (this repo)

The toolchain is published as GitHub Releases on the **psyup repo itself**
(no separate `psy-toolchain` repo). Each tag `vX.Y.Z` ships four tarballs
plus a checksum file:

```
psy-toolchain-vX.Y.Z-aarch64-apple-darwin.tar.gz
psy-toolchain-vX.Y.Z-x86_64-apple-darwin.tar.gz
psy-toolchain-vX.Y.Z-aarch64-unknown-linux-gnu.tar.gz
psy-toolchain-vX.Y.Z-x86_64-unknown-linux-gnu.tar.gz
SHA256SUMS                                          # one line per tarball
```

Override the source repo with `PSYUP_TOOLCHAIN_REPO=owner/repo` if you need
to point at a fork.

Each tarball expands to:

```
<toolchain-root>/
├── bin/
│   ├── dargo              # contract compiler (psy-compiler)
│   ├── psy_user_cli       # wallet, deploy-contract, call, withdraw, ...
│   ├── psy_worker_cli     # run a worker node
│   ├── psy_node_cli       # run coordinator / realm processors
│   ├── psy_dev_cli        # dev/debug utilities (read backups, etc.)
│   └── psy_relayer_cli    # bridge relayer
├── lib/
│   └── psy-std/           # bundled stdlib (must contain std.psy + prelude.psy)
│       ├── std.psy
│       ├── prelude.psy
│       └── ...
└── config.json            # RPC network config
```

`psyup install` symlinks every file in `bin/` into `~/.psy/bin/`, so all six
binaries are on PATH after install.

After `psyup install`, `~/.psy/env` is rewritten to export
`DARGO_STD_PATH=<toolchain-root>/lib/psy-std/std.psy` so the compiler can find
the stdlib without falling back to a git clone. It also installs the
toolchain's `config.json` to `~/.psy/config.json` and exports
`RPC_CONFIG=~/.psy/config.json` for `psy_user_cli`. `psyup build` also sets
`DARGO_STD_PATH` defensively in case the shell didn't source `~/.psy/env`.
Set `PSYUP_DEFAULT_NETWORK=<name>` before running `install.sh` or
`psyup install` to choose the default network; otherwise it defaults to
`localhost`.

### `logere/psy-template`

Multi-template repo — each top-level directory is one named template.
`psyup new` downloads the repo's `main` tarball and extracts the requested
subdir. Currently only `dapp/` exists; new templates are added by dropping a
new directory at the repo root.

```
psy-template/
└── dapp/                           # default — React + contract starter
    ├── package.json                # top-level frontend manifest
    ├── index.html
    ├── tsconfig.json
    ├── vite.config.ts
    ├── src/                        # React app
    │   ├── App.tsx
    │   ├── main.tsx
    │   ├── components/{ConnectBar,TokenPanel,TxLog}.tsx
    │   ├── hooks/usePsy.ts
    │   ├── lib/{psy,token}.ts
    │   └── config.ts
    └── contract/                   # PSY contract sub-package
        ├── Dargo.toml
        └── src/main.psy
```

Selection:

| invocation | result |
|---|---|
| `psyup new my-app` | default subdir = `$PSYUP_DEFAULT_TEMPLATE` (currently `dapp`) |
| `psyup new my-app --template <key>` | `<key>/` subdir of `logere/psy-template` |
| `psyup new my-app --template owner/repo` | that repo's whole `main` archive |
| `psyup new my-app --template owner/repo#sub` | `sub/` subdir of that repo |
| `psyup new my-app --template https://...tar.gz[#sub]` | direct tarball URL (with optional subdir) |

After extraction, `psyup new` rewrites the project name in (where present):
`Dargo.toml`, `contract/Dargo.toml`, and the top-level `package.json`.

## Development

```sh
# run dispatcher from a checkout (no need to install globally)
./psyup help

# end-to-end smoke test — uses fake psyc/psy-cli stubs and a local tarball,
# no network, no real toolchain required
bash test/smoke.sh
```

## Out of scope (v0.1)

- Windows (only macOS + Linux for now)
- Local test chain / anvil-equivalent
- Wallet & key management (bring your own keyfile)
- `psyup self update` (just re-run `install.sh`)
