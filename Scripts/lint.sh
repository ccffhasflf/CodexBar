#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./Scripts/install_lint_tools.sh swiftformat swiftlint
if [[ "${1:-lint}" == format ]]; then
    .build/lint-tools/bin/swiftformat Sources Tests Package.swift
else
    .build/lint-tools/bin/swiftformat Sources Tests Package.swift --lint
    .build/lint-tools/bin/swiftlint lint --strict --quiet
fi
