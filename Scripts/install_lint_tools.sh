#!/bin/bash
# Same pinned SwiftFormat/SwiftLint releases as the upstream baseline; macOS only.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN_DIR="$PWD/.build/lint-tools/bin"
mkdir -p "$BIN_DIR"
install_tool() {
    local name="$1" version="$2" version_arg="$3" url="$4" expected="$5"
    if [[ -x "$BIN_DIR/$name" ]] && [[ "$("$BIN_DIR/$name" "$version_arg")" == "$version" ]]; then
        return
    fi
    local temporary
    temporary="$(mktemp -d "$PWD/.build/lint-tools/download.XXXXXX")"
    curl --fail --location --silent --show-error "$url" -o "$temporary/tool.zip"
    local actual
    actual="$(shasum -a 256 "$temporary/tool.zip" | cut -d ' ' -f 1)"
    if [[ "$actual" != "$expected" ]]; then
        printf 'Checksum mismatch for %s\n' "$name" >&2
        rm -rf "$temporary"
        exit 1
    fi
    unzip -q "$temporary/tool.zip" -d "$temporary/unpacked"
    install -m 755 "$temporary/unpacked/$name" "$BIN_DIR/$name"
    rm -rf "$temporary"
}
install_tool swiftformat 0.63.0 --version \
    https://github.com/nicklockwood/SwiftFormat/releases/download/0.63.0/swiftformat.zip \
    28c7802e11fa5ae113d903066439c6bb1be20a8ac1ad9709c42616a7e273fb0f
install_tool swiftlint 0.65.1 version \
    https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip \
    c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
