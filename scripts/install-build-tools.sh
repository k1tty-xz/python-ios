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

# Install only missing formulas. Fully qualify official Homebrew core so an
# unrelated third-party tap cannot affect or warn during dependency setup.
for f in "${FORMULAE[@]}"; do
  if brew list --formula | grep -qx "${f}"; then
    echo "Info: ${f} is already installed. Skipping..."
  else
    brew install "homebrew/core/${f}"
  fi
done
