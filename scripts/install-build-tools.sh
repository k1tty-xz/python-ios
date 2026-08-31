#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

FORMULAE=(dpkg ldid pkgconf)

for formula in "${FORMULAE[@]}"; do
  if brew list --formula "$formula" >/dev/null 2>&1; then
    echo "Info: $formula is already installed. Skipping..."
  else
    brew install "$formula"
  fi
done
