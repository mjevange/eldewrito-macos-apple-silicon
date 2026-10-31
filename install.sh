#!/bin/bash
#
# ElDewrito 0.7.1 installer for Apple Silicon Macs.
#
#   bash install.sh            # install
#   bash install.sh --check    # verify prerequisites only, change nothing
#   bash install.sh --prepare  # everything except running the launcher wizard
#   bash install.sh --uninstall
#
# Follows the official guide's macOS steps 2-8 unchanged
# (https://docs.google.com/document/d/1-hdCc9V0zTvX38sruTNRBiBSJdz5B5s0M7AH9Yy5_0k/edit)
# and resolves its step 1 with a Wine build verified to run the launcher.
#
# See docs/FINDINGS.md for why this specific runtime, and what fails.

set -euo pipefail

RUNTIME_URL="https://github.com/frankea/winecx-gptk/releases/download/runtime-v4.6.4/Libraries.tar.gz"
LAUNCHER_URL="https://github.com/eldewrito2/ElDewritoLauncher/releases/download/0.1.1/launcher.exe"
DOTNET_URL="https://aka.ms/dotnet/6.0/windowsdesktop-runtime-win-x64.exe"
DOTNET_FALLBACK="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/6.0.36/windowsdesktop-runtime-6.0.36-win-x64.exe"

RUNTIME_DIR="${ELDEW_RUNTIME:-$HOME/.eldewrito/runtime}"
PREFIX="${WINEPREFIX:-$HOME/my-game-prefix}"
GAME_DIR="$PREFIX/drive_c/Program Files/ElDewrito"
WINE="$RUNTIME_DIR/Libraries/Wine/lib/wine/x86_64-unix/wine"

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '    \033[1;33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ----------------------------------------------------------------- checks
preflight() {
    say "Checking this Mac"

    [ "$(uname -m)" = "arm64" ] || die "Apple Silicon required; this is $(uname -m).
GPTK is built on D3DMetal and Rosetta 2, neither of which exists on Intel.
Intel Macs need CrossOver, Kegworks or Boot Camp - not covered here."
    ok "Apple Silicon"

    local v major
    v="$(sw_vers -productVersion)"; major="${v%%.*}"
    [ "$major" -ge 14 ] || die "macOS 14 (Sonoma) or newer required; found $v"
    ok "macOS $v"

    local free
    free="$(df -g "$HOME" | awk 'NR==2{print $4}')"
    [ "${free:-0}" -ge 15 ] || die "Need ~15GB free, found ${free}GB"
    ok "${free}GB free"

    if /usr/bin/pgrep -q oahd; then
        ok "Rosetta 2 present"
    else
        warn "Rosetta 2 missing - will install (a system component, not a macOS update)"
    fi
}

# ----------------------------------------------------------------- install
install_runtime() {
    say "Wine runtime"
    if [ -x "$WINE" ]; then
        ok "already present: $("$WINE" --version 2>/dev/null || echo unknown)"
        return
    fi
    /usr/bin/pgrep -q oahd || softwareupdate --install-rosetta --agree-to-license
    mkdir -p "$RUNTIME_DIR"
    echo "    downloading (459MB)..."
    curl -fL --retry 3 --progress-bar -o "$RUNTIME_DIR/rt.tar.gz" "$RUNTIME_URL"
    tar -xzf "$RUNTIME_DIR/rt.tar.gz" -C "$RUNTIME_DIR"
    rm -f "$RUNTIME_DIR/rt.tar.gz"
    # Gatekeeper flags downloaded binaries; Homebrew's --no-quarantine is gone.
    xattr -dr com.apple.quarantine "$RUNTIME_DIR" 2>/dev/null || true
    [ -x "$WINE" ] || die "wine binary not found after extraction at $WINE"
    ok "$("$WINE" --version)"
}

create_prefix() {
    say "Wine prefix at $PREFIX"
    export WINEPREFIX="$PREFIX" WINEDEBUG=-all
    if [ -d "$PREFIX/drive_c/windows" ]; then
        ok "already initialised"
    else
        "$WINE" wineboot --init >/dev/null 2>&1 || true
        sleep 40
        [ -d "$PREFIX/drive_c/windows" ] || die "prefix did not initialise"
        ok "created"
    fi
    mkdir -p "$PREFIX/drive_c/stage"
    "$WINE" cmd /c ver 2>/dev/null | tr -d '\r' | sed 's/^/    /' || true
}

install_dotnet() {
    say ".NET 6 Desktop Runtime (guide step 5)"
    export WINEPREFIX="$PREFIX" WINEDEBUG=-all
    if [ -d "$PREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App" ]; then
        ok "already installed: $(ls "$PREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App" | tr '\n' ' ')"
        return
    fi
    cd "$PREFIX/drive_c/stage"
    curl -fL --progress-bar -o dotnet.exe "$DOTNET_URL" \
        || curl -fL --progress-bar -o dotnet.exe "$DOTNET_FALLBACK" \
        || die "could not download the .NET runtime"
    "$WINE" 'C:\stage\dotnet.exe' /quiet /norestart >/dev/null 2>&1 || true
    sleep 10
    # Verify rather than assume - this step can fail silently.
    [ -d "$PREFIX/drive_c/Program Files/dotnet/shared/Microsoft.WindowsDesktop.App" ] \
        || die ".NET did not install. Re-run; if it persists see docs/FINDINGS.md"
    ok "installed"
}

stage_launcher() {
    say "Staging the launcher"
    # The launcher installs into its own directory, so stage it where the
    # game should live rather than in a scratch folder.
    mkdir -p "$GAME_DIR"
    cd "$GAME_DIR"
    [ -f launcher.exe ] || curl -fL --progress-bar -o launcher.exe "$LAUNCHER_URL"
    ok "launcher.exe staged in $GAME_DIR"
}

run_launcher() {
    say "ElDewrito launcher (guide step 6)"
    export WINEPREFIX="$PREFIX" WINEDEBUG=-all
    # The launcher installs into its own directory, so stage it where the
    # game should live rather than in a scratch folder.
    mkdir -p "$GAME_DIR"
    cd "$GAME_DIR"
    [ -f launcher.exe ] || curl -fL --progress-bar -o launcher.exe "$LAUNCHER_URL"
    cat <<'EOF'

    The installer window will open. In it:
      - set the install path to  C:\Program Files\ElDewrito
      - ALLOW the firewall prompt
      - ALLOW the macOS prompt "find devices on local networks"
        (both are required; denying either stalls the download at 0%)

EOF
    "$WINE" 'C:\Program Files\ElDewrito\launcher.exe' || true
}

# The launcher installs beside itself, and a user may have pointed it
# elsewhere, so locate eldorado.exe rather than assuming.
find_game() {
    local hit
    hit="$(find "$PREFIX/drive_c" -maxdepth 5 -iname eldorado.exe 2>/dev/null | head -1)"
    [ -n "$hit" ] && dirname "$hit"
}

configure() {
    say "Config (guide step 7)"
    local found; found="$(find_game || true)"
    [ -n "$found" ] && GAME_DIR="$found"
    local cfg="$GAME_DIR/data/dewrito_prefs.cfg"
    [ -d "$GAME_DIR" ] || { warn "game not found - run the launcher first, then re-run this script"; return; }
    ok "game at $GAME_DIR"
    mkdir -p "$(dirname "$cfg")"; touch "$cfg"
    if grep -q '^Game.CEFGpuEnable' "$cfg" 2>/dev/null; then
        sed -i '' 's/^Game.CEFGpuEnable.*/Game.CEFGpuEnable 0/' "$cfg"
    else
        echo 'Game.CEFGpuEnable 0' >> "$cfg"
    fi
    ok "Game.CEFGpuEnable 0"
}

write_play_script() {
    say "Play script"
    local p="$HOME/Desktop/Play ElDewrito.command"
    cat > "$p" <<EOF
#!/bin/bash
# Launch ElDewrito. Guide step 8: esync disabled.
export WINEPREFIX="$PREFIX"
export WINEDEBUG=-all
# The official guide says esync off. On Wine 11.16 esync and msync both work
# for the launcher, but in-game effects are untested, so default stays off.
#   ELDEW_SYNC=esync|msync to try them.
case "${ELDEW_SYNC:-off}" in
  esync) export WINEESYNC=1 ;;
  msync) export WINEMSYNC=1; export WINEESYNC=0 ;;
  *)     export WINEESYNC=0 ;;
esac
GAME="$GAME_DIR"
if [ ! -f "\$GAME/eldorado.exe" ]; then
  GAME="\$(find "$PREFIX/drive_c" -maxdepth 5 -iname eldorado.exe 2>/dev/null | head -1 | xargs -r dirname)"
fi
[ -n "\$GAME" ] || { echo "eldorado.exe not found - run the launcher first"; read -r _; exit 1; }
cd "\$GAME" || exit 1
exec "$WINE" eldorado.exe "\$@"
EOF
    chmod +x "$p"
    ok "$p"
    echo "    First open: right-click → Open, to clear Gatekeeper."
    echo "    Plug in a gamepad BEFORE launching, per the official guide."
}

uninstall() {
    say "Removing ElDewrito"
    rm -rf "$PREFIX" "$RUNTIME_DIR"
    rm -f "$HOME/Desktop/Play ElDewrito.command"
    ok "removed prefix, runtime and play script"
    echo "    Rosetta 2 is left in place; it is inert when unused."
}

# ----------------------------------------------------------------- main
case "${1:-}" in
    --check)     preflight; say "Prerequisites OK - nothing was changed"; exit 0 ;;
    --prepare)   # everything except the interactive wizard, so CI can test this script
                 preflight; install_runtime; create_prefix; install_dotnet
                 stage_launcher; write_play_script
                 say "Prepared. Run the launcher to download the game:"
                 echo "    \"$WINE\" 'C:\\Program Files\\ElDewrito\\launcher.exe'"
                 exit 0 ;;
    --uninstall) uninstall; exit 0 ;;
    -h|--help)   sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

preflight
install_runtime
create_prefix
install_dotnet
stage_launcher
run_launcher
configure
write_play_script

say "Done"
echo "    Play:   double-click  ~/Desktop/Play ElDewrito.command"
echo "    Update: bash install.sh   (re-runs the launcher, which self-updates)"
echo
echo "    Did the game run? Please report it:"
echo "    https://github.com/mjevange/eldewrito-macos-apple-silicon/issues/new/choose"
