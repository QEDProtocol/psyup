# psyup

One-shot installer + project scaffolder for the PSY smart-contract toolchain.
Inspired by `rustup` / `foundryup`.

```sh
curl -fsSL https://raw.githubusercontent.com/QEDProtocol/psyup/main/install.sh | sh
source ~/.psy/env

psyup install            # download psyc + psy-cli
psyup new my-token       # scaffold from the boilerplate
cd my-token
psyup build              # compile
psyup deploy             # deploy to the configured network
```

No manual cloning, no source builds, no chasing dependencies.

## Commands

| Command | What it does |
|---|---|
| `psyup install [version]` | Download the PSY toolchain release for your platform, verify SHA256, symlink into `~/.psy/bin`. Defaults to `latest`. |
| `psyup update` | Re-resolve `latest` and reinstall if newer. |
| `psyup uninstall` | Remove `~/.psy` (asks first). |
| `psyup new <name> [--template <git-url-or-owner/repo>]` | Download a template tarball, rename the project in `psy.toml`, optionally `git init`. |
| `psyup build [args...]` | Run `psyc build` in the current project. |
| `psyup deploy [--network N] [--rpc URL] [--key path]` | Run `psy-cli deploy` against the configured network. |

## Layout

```
~/.psy/
├── bin/            # psyup + symlinks to active toolchain
├── toolchains/     # versioned: psy-<ver>/bin/{psyc, psy-cli}
├── lib/            # psyup's own bash modules (installed by install.sh)
├── templates/      # cache (reserved)
├── env             # source this to add ~/.psy/bin to PATH
└── settings.toml   # active version, default RPC, networks
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
└── lib/
    └── psy-std/           # bundled stdlib (must contain std.psy + prelude.psy)
        ├── std.psy
        ├── prelude.psy
        └── ...
```

`psyup install` symlinks every file in `bin/` into `~/.psy/bin/`, so all six
binaries are on PATH after install.

After `psyup install`, `~/.psy/env` is rewritten to
`export DARGO_STD_PATH=<toolchain-root>/lib/psy-std/std.psy` so the compiler
can find the stdlib without falling back to a git clone. `psyup build` also
sets this defensively in case the shell didn't source `~/.psy/env`.

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
