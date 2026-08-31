#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common-env.sh"

if [[ -f "$MPDECIMAL_PREFIX/lib/libmpdec.a" ]] &&
   [[ -f "$MPDECIMAL_PREFIX/lib/pkgconfig/libmpdec.pc" ]] &&
   grep -Fqx "prefix=$MPDECIMAL_PREFIX" "$MPDECIMAL_PREFIX/lib/pkgconfig/libmpdec.pc"; then
  echo "Info: mpdecimal already built. Skipping..."
  exit 0
fi

rm -rf "$DEPS/mpdecimal-ios"

cd "$DEPS"

MPDECIMAL_TAR="mpdecimal-${MPDECIMAL_VER}.tar.gz"
MPDECIMAL_URL="https://www.bytereef.org/software/mpdecimal/releases/$MPDECIMAL_TAR"
fetch_verified "$MPDECIMAL_URL" "$DEPS/$MPDECIMAL_TAR" "$MPDECIMAL_SHA256"
tar xf "$MPDECIMAL_TAR"
cd "mpdecimal-${MPDECIMAL_VER}"

./configure \
  --host="$HOST_TRIPLE" \
  --prefix="$MPDECIMAL_PREFIX" \
  --disable-shared \
  --enable-static

make -j"$JOBS"
make install

cd "$DEPS"
rm -rf "mpdecimal-${MPDECIMAL_VER}" "$MPDECIMAL_TAR"
