# psyup new <name> [--template <key|owner/repo|url>]
#
# Template resolution:
#   --template <key>        → $PSYUP_BOILERPLATE_REPO/main.tar.gz, extract <key>/ subdir
#   --template <owner/repo> → that repo's main.tar.gz, use top-level
#   --template <url>        → fetch tarball directly, use top-level
#   (no --template)         → $PSYUP_BOILERPLATE_REPO + $PSYUP_DEFAULT_TEMPLATE subdir

cmd_new() {
    need curl
    need tar

    local name="" template=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --template) template=${2:-}; shift 2 ;;
            --template=*) template=${1#--template=}; shift ;;
            -*) die "unknown option: $1" ;;
            *) [ -z "$name" ] && name=$1 || die "unexpected arg: $1"; shift ;;
        esac
    done

    [ -n "$name" ] || die "usage: psyup new <name> [--template <key|owner/repo|url>]"
    case "$name" in
        */*|.|..) die "invalid project name: $name" ;;
    esac
    [ -e "$name" ] && die "path already exists: $name"

    # Optional `#subdir` suffix on URL / owner-repo forms picks a directory
    # inside the tarball. Bare keys map to a subdir of the default repo.
    local url subdir=""
    local template_body=$template template_subdir=""
    case "$template" in
        *'#'*)
            template_body=${template%%#*}
            template_subdir=${template#*#}
            ;;
    esac

    if [ -z "$template_body" ]; then
        url="https://github.com/${PSYUP_BOILERPLATE_REPO}/archive/refs/heads/main.tar.gz"
        subdir=${template_subdir:-$PSYUP_DEFAULT_TEMPLATE}
    else
        case "$template_body" in
            http*://*|file://*)
                url=$template_body
                subdir=$template_subdir
                ;;
            */*)
                url="https://github.com/${template_body}/archive/refs/heads/main.tar.gz"
                subdir=$template_subdir
                ;;
            *)
                url="https://github.com/${PSYUP_BOILERPLATE_REPO}/archive/refs/heads/main.tar.gz"
                subdir=${template_subdir:-$template_body}
                ;;
        esac
    fi

    local tmp
    tmp=$(mktemp -d)

    say "fetching template from $url${subdir:+ (subdir: $subdir)}"
    curl -fsSL "$url" -o "$tmp/template.tar.gz" \
        || die "failed to download template"

    mkdir -p "$tmp/extract"
    tar -xzf "$tmp/template.tar.gz" -C "$tmp/extract" \
        || die "failed to extract template"

    # GitHub tarballs always have exactly one top-level dir.
    local top
    top=$(find "$tmp/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)
    [ -n "$top" ] || die "template archive is empty"

    local source_dir
    if [ -n "$subdir" ]; then
        source_dir="$top/$subdir"
        [ -d "$source_dir" ] || die "template '$subdir' not found in archive (expected $source_dir)"
    else
        source_dir=$top
    fi

    mv "$source_dir" "$name"

    # Rewrite project name in any top-level manifests we find.
    rewrite_name_field "$name/Dargo.toml" "$name"
    rewrite_name_field "$name/contract/Dargo.toml" "$name"
    rewrite_package_json_name "$name/package.json" "$name"

    if command -v git >/dev/null 2>&1; then
        (
            cd "$name"
            rm -rf .git
            git init -q
            git add -A
            git -c user.email=psyup@local -c user.name=psyup \
                commit -q -m "init from psyup template" || true
        )
    fi

    rm -rf "$tmp"

    say "created $name/"
    if [ -d "$name/contract" ]; then
        say "next: cd $name/contract && psyup build"
    else
        say "next: cd $name && psyup build"
    fi
}

# Replace a top-level `name = "..."` line in a TOML file.
rewrite_name_field() {
    local file=$1 new=$2
    [ -f "$file" ] || return 0
    local tmpf
    tmpf=$(mktemp)
    awk -v n="$new" '
        /^name[[:space:]]*=/ && !done { print "name = \"" n "\""; done=1; next }
        { print }
    ' "$file" > "$tmpf" && mv "$tmpf" "$file"
}

# Replace `"name": "..."` in package.json (first occurrence only — the top one).
rewrite_package_json_name() {
    local file=$1 new=$2
    [ -f "$file" ] || return 0
    local tmpf
    tmpf=$(mktemp)
    awk -v n="$new" '
        !done && /"name"[[:space:]]*:[[:space:]]*"/ {
            sub(/"name"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"name\": \"" n "\"")
            done=1
        }
        { print }
    ' "$file" > "$tmpf" && mv "$tmpf" "$file"
}
