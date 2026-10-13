#!/usr/bin/env bash
# Downloads the dimos-desktop binary for this machine and runs its installer.
#   curl -fsSL https://raw.githubusercontent.com/jeff-hykin/dimos-desktop-mirror/main/install.sh | bash
# Arguments after `bash -s --` go to `dimos-desktop setup` (see `dimos-desktop setup --help`).
# DIMOS_DESKTOP_REPO    GitHub owner/repo to download from (default jeff-hykin/dimos-desktop-mirror, the public mirror;
#                       a release's copy: its own repo)
# DIMOS_DESKTOP_VERSION release tag (default: the latest release; a release's copy: that release)
# DIMOS_DESKTOP_BINARY  use this local binary instead of downloading one
# DIMOS_YES=1           replace an installed Desktop without asking (like `bash -s -- --yes`)
set -euo pipefail

repo="${DIMOS_DESKTOP_REPO:-jeff-hykin/dimos-desktop-mirror}"
version="${DIMOS_DESKTOP_VERSION:-latest}"

fail() {
    printf 'dimos-desktop install: %s\n' "$1" >&2
    exit 1
}

case "$(uname -s)" in
    Linux) os="unknown-linux-gnu" ;;
    Darwin) os="apple-darwin" ;;
    *) fail "unsupported OS $(uname -s); Linux and macOS are supported" ;;
esac
case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    arm64 | aarch64) arch="aarch64" ;;
    *) fail "unsupported CPU $(uname -m); x86_64 and arm64 are supported" ;;
esac
asset="dimos-desktop-${arch}-${os}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
binary="$workdir/dimos-desktop"

if [ -n "${DIMOS_DESKTOP_BINARY:-}" ]; then
    cp "$DIMOS_DESKTOP_BINARY" "$binary"
else
    if [ "$version" = "latest" ]; then
        url="https://github.com/$repo/releases/latest/download/$asset"
    else
        url="https://github.com/$repo/releases/download/$version/$asset"
    fi
    if [ "$version" = "latest" ] && ! curl -fsLI -o /dev/null "$url"; then
        # the newest release may still be building this machine's binary (each platform's joins it when built): take the newest
        # release that has it
        newest="$(curl -fsL "https://api.github.com/repos/$repo/releases?per_page=20" 2>/dev/null |
            grep -o "\"browser_download_url\": *\"[^\"]*/$asset\"" | head -n 1 | sed 's/.*: *"//; s/"$//' || true)"
        [ -n "$newest" ] && url="$newest"
    fi
    printf 'Downloading %s\n' "$url"
    if ! curl -fL --progress-bar -o "$binary" "$url"; then
        # a private repo's release needs auth; gh has it if you're logged in
        if command -v gh >/dev/null 2>&1; then
            tag_args=()
            [ "$version" != "latest" ] && tag_args=("$version")
            gh release download "${tag_args[@]}" --repo "$repo" --pattern "$asset" --output "$binary" --clobber ||
                fail "couldn't download $asset from $repo"
        else
            fail "couldn't download $url"
        fi
    fi
fi
chmod +x "$binary"
# macOS quarantines downloads; the binary isn't notarized
if [ "$(uname -s)" = "Darwin" ]; then
    xattr -d com.apple.quarantine "$binary" 2>/dev/null || true
fi

# over SSH no browser opens here: setup opens it on your computer through VS Code's Remote-SSH terminal when it can, and
# otherwise prints an ssh tunnel, the network URL and how to finish in this terminal
if [ -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" ]; then
    printf 'Over SSH: once Desktop is up, setup says how to open it from the computer you are at.\n'
fi

# `curl | bash` gives this script the pipe as stdin; hand the installer the terminal for its prompts. With no terminal,
# setup returns once Desktop is up (the install goes on in the browser) and won't replace an existing Desktop unless
# given --yes (or DIMOS_YES=1)
if [ -t 1 ] && { : </dev/tty; } 2>/dev/null; then
    "$binary" setup "$@" </dev/tty
else
    "$binary" setup "$@"
fi
