#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

for formula in dpkg ldid pkgconf shellcheck; do
  brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
done
