#!/usr/bin/env bash
set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

FORMULAE=(dpkg ldid pkg-config)

# Install only missing formulas, resolving each dependency from official core.
for f in "${FORMULAE[@]}"; do
  if brew list --formula | grep -qx "${f}" ||
     [[ "${f}" == pkg-config ]] && brew list --formula | grep -qx pkgconf; then
    echo "Info: ${f} is already installed. Skipping..."
  else
    brew install "homebrew/core/${f}"
  fi
done
