#!/bin/sh
# Sesame secretctl installer
# Usage: curl -fsSL https://getsesame.dev/install.sh | sh
set -eu

REPO="getsesame/secretctl"
BINARY_NAME="secretctl"
DEFAULT_PREFIX="/usr/local/bin"

# --- Output helpers ---

has_tty() { [ -t 1 ]; }

if has_tty; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD='' DIM='' GREEN='' RED='' YELLOW='' CYAN='' RESET=''
fi

info()  { printf "  %b\n" "$*"; }
ok()    { printf "  %b%b%b\n" "$GREEN" "$*" "$RESET"; }
warn()  { printf "  %b%b%b\n" "$YELLOW" "$*" "$RESET"; }
err()   { printf "  %b%b%b\n" "$RED" "$*" "$RESET" >&2; }
die()   { err "$@"; exit 1; }

# --- Argument parsing ---

VERSION=""
PREFIX=""
UNINSTALL=0
HELP=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version)  VERSION="$2"; shift 2 ;;
        --prefix)   PREFIX="$2"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        --help|-h)  HELP=1; shift ;;
        *) die "Unknown option: $1. Run with --help for usage." ;;
    esac
done

if [ "$HELP" = 1 ]; then
    cat <<'USAGE'
Sesame secretctl installer

Usage:
    curl -fsSL https://getsesame.dev/install.sh | sh
    curl -fsSL https://getsesame.dev/install.sh | sh -s -- [OPTIONS]

Options:
    --version <ver>    Install a specific version (e.g., v0.1.0)
    --prefix <dir>     Install location (default: /usr/local/bin)
    --uninstall        Remove secretctl
    --help             Show this message
USAGE
    exit 0
fi

# --- Platform detection ---

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "$OS" in
        Darwin) OS="darwin" ;;
        Linux)  OS="linux" ;;
        *)      die "Unsupported OS: $OS" ;;
    esac

    case "$ARCH" in
        x86_64|amd64)   ARCH="x86_64" ;;
        arm64|aarch64)  ARCH="arm64" ;;
        *)              die "Unsupported architecture: $ARCH" ;;
    esac

    PLATFORM="${OS}-${ARCH}"
}

# --- Version resolution ---

resolve_version() {
    if [ -n "$VERSION" ]; then
        # Ensure version starts with 'v'
        case "$VERSION" in
            v*) ;;
            *)  VERSION="v${VERSION}" ;;
        esac
        return
    fi

    info "Fetching latest version..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

    if [ -z "$VERSION" ]; then
        die "Could not determine latest version. Specify one with --version."
    fi
}

# --- Install location ---

resolve_prefix() {
    if [ -n "$PREFIX" ]; then
        return
    fi

    if [ -w "$DEFAULT_PREFIX" ]; then
        PREFIX="$DEFAULT_PREFIX"
    elif [ -w "$HOME/.local/bin" ] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
        PREFIX="$HOME/.local/bin"
    else
        PREFIX="$DEFAULT_PREFIX"
    fi
}

ensure_writable() {
    if [ ! -w "$PREFIX" ]; then
        err "Cannot write to ${PREFIX}"
        info ""
        info "Run with sudo:"
        info "  ${CYAN}curl -fsSL https://getsesame.dev/install.sh | sudo sh${RESET}"
        info ""
        info "Or install to ~/.local/bin:"
        info "  ${CYAN}curl -fsSL https://getsesame.dev/install.sh | sh -s -- --prefix ~/.local/bin${RESET}"
        exit 1
    fi
}

# --- PATH check ---

check_path() {
    case ":$PATH:" in
        *":${PREFIX}:"*) return 0 ;;
    esac

    SHELL_NAME="$(basename "${SHELL:-/bin/sh}")"
    case "$SHELL_NAME" in
        zsh)  PROFILE="$HOME/.zshrc" ;;
        bash) PROFILE="$HOME/.bashrc" ;;
        *)    PROFILE="$HOME/.profile" ;;
    esac

    warn "${PREFIX} is not in your PATH."
    info ""
    info "Add it by running:"
    info "  ${CYAN}echo 'export PATH=\"${PREFIX}:\$PATH\"' >> ${PROFILE}${RESET}"
    info "  ${CYAN}source ${PROFILE}${RESET}"
    info ""
}

# --- Uninstall ---

do_uninstall() {
    resolve_prefix
    TARGET="${PREFIX}/${BINARY_NAME}"

    printf "\n"
    info "${BOLD}sesame${RESET} - secret broker CLI"
    info ""

    if [ ! -f "$TARGET" ]; then
        warn "secretctl is not installed at ${TARGET}"
        exit 0
    fi

    rm -f "$TARGET"
    ok "secretctl removed from ${TARGET}"
    exit 0
}

# --- Download and verify ---

download_binary() {
    BINARY_FILE="${BINARY_NAME}-${PLATFORM}"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${BINARY_FILE}"
    CHECKSUM_URL="${DOWNLOAD_URL}.sha256"
    TMP_DIR="$(mktemp -d)"

    trap 'rm -rf "$TMP_DIR"' EXIT

    printf "  Downloading secretctl %b%s%b... " "$BOLD" "$VERSION" "$RESET"
    if ! curl -fsSL -o "${TMP_DIR}/${BINARY_FILE}" "$DOWNLOAD_URL"; then
        printf "\n"
        die "Download failed. Check that version ${VERSION} exists at:"
        die "  https://github.com/${REPO}/releases/tag/${VERSION}"
    fi
    printf "done\n"

    printf "  Verifying checksum... "
    if curl -fsSL -o "${TMP_DIR}/${BINARY_FILE}.sha256" "$CHECKSUM_URL" 2>/dev/null; then
        EXPECTED="$(awk '{print $1}' "${TMP_DIR}/${BINARY_FILE}.sha256")"
        if command -v sha256sum >/dev/null 2>&1; then
            ACTUAL="$(sha256sum "${TMP_DIR}/${BINARY_FILE}" | awk '{print $1}')"
        else
            ACTUAL="$(shasum -a 256 "${TMP_DIR}/${BINARY_FILE}" | awk '{print $1}')"
        fi

        if [ "$EXPECTED" != "$ACTUAL" ]; then
            printf "\n"
            die "Checksum mismatch! Expected ${EXPECTED}, got ${ACTUAL}."
            die "The download may be corrupted. Please try again."
        fi
        printf "ok\n"
    else
        warn "skipped (no checksum file found)"
    fi

    chmod +x "${TMP_DIR}/${BINARY_FILE}"
    mv "${TMP_DIR}/${BINARY_FILE}" "${PREFIX}/${BINARY_NAME}"
}

# --- Skill install ---

install_skill() {
    # First -y is for npx (auto-accept package install).
    # --yes --global --all pass through to the `skills` CLI itself: skip every
    # confirmation, install to the user-level agent dir, and target every
    # detected agent. </dev/null forces the prompt library to give up
    # immediately on its TTY check instead of hanging when stdin is the
    # curl-piped installer.
    SKILL_CMD="npx -y skills add getsesame/skills --yes --global --all"
    SKILL_MANUAL="npx skills add getsesame/skills"

    if ! command -v npx >/dev/null 2>&1; then
        info "${BOLD}Install Sesame skill${RESET} (requires Node.js)"
        info "  ${CYAN}${SKILL_MANUAL}${RESET}"
        info ""
        return
    fi

    info "${BOLD}Installing Sesame skill...${RESET}"
    if $SKILL_CMD </dev/null; then
        ok "Sesame skill installed"
    else
        warn "Skill install failed. Run manually:"
        info "  ${CYAN}${SKILL_MANUAL}${RESET}"
    fi
    info ""
}

# --- Existing install detection ---

check_existing() {
    TARGET="${PREFIX}/${BINARY_NAME}"
    if [ -f "$TARGET" ]; then
        CURRENT="$("$TARGET" --version 2>/dev/null || echo "unknown")"
        info "Current:   ${DIM}${CURRENT}${RESET}"
        info "Latest:    ${BOLD}${VERSION}${RESET}"
        info ""
    fi
}

# --- Main ---

main() {
    if [ "$UNINSTALL" = 1 ]; then
        do_uninstall
    fi

    detect_platform
    resolve_version
    resolve_prefix
    ensure_writable

    printf "\n"
    info "${BOLD}sesame${RESET} - secret broker CLI"
    info ""
    info "Platform:  ${OS} (${ARCH})"
    info "Location:  ${PREFIX}/${BINARY_NAME}"
    info ""

    check_existing
    download_binary

    info ""
    ok "secretctl installed successfully!"
    info ""

    install_skill

    info "Get started:"
    info "  ${CYAN}secretctl login${RESET}       Register this device"
    info "  ${CYAN}secretctl status${RESET}      Check agent status"
    info "  ${CYAN}secretctl --help${RESET}      See all commands"
    info ""
    info "Docs: ${CYAN}https://getsesame.dev/docs${RESET}"
    printf "\n"

    check_path
}

main
