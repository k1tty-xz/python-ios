#!/usr/bin/env bash
# ==============================================================================
# Script: install-build-tools.sh
# Purpose: Install required build tools via Homebrew (macOS).
# Usage: Run on the CI runner or local macOS machine.
# ==============================================================================

set -euxo pipefail

# ------------------------------------------------------------------------------
# Homebrew Configuration
# ------------------------------------------------------------------------------
# Optimize Homebrew to avoid time-consuming updates and cleanup during CI.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1

# ------------------------------------------------------------------------------
# Install Dependencies
# ------------------------------------------------------------------------------
# Only install tools that are not already provided by macOS/Xcode.
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
