#!/bin/bash
# Builds a .deb installer for GitOpen.
#
# Usage: scripts/build-deb.sh [VERSION]
# Default version: the one in pubspec.yaml, normalized to x.y.z.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Pull the version from pubspec.yaml unless one was given explicitly, and
# strip the optional `+build` suffix so it conforms to Debian's policy.
VERSION="${1:-$(awk '/^version:/{print $2}' pubspec.yaml | cut -d+ -f1)}"
PKG_DIR="build/deb-staging/gitopen_${VERSION}_amd64"
OUT="build/gitopen_${VERSION}_amd64.deb"

flutter build linux --release

rm -rf build/deb-staging
mkdir -p "${PKG_DIR}/DEBIAN" \
         "${PKG_DIR}/opt/gitopen" \
         "${PKG_DIR}/usr/bin" \
         "${PKG_DIR}/usr/share/applications" \
         "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps"

# App lives in /opt so the bundled libs ship next to the binary.
cp -r build/linux/x64/release/bundle/. "${PKG_DIR}/opt/gitopen/"
cp assets/icon/app_icon.png \
   "${PKG_DIR}/usr/share/icons/hicolor/256x256/apps/gitopen.png"

# Tiny shim so `gitopen` is callable from PATH.
cat > "${PKG_DIR}/usr/bin/gitopen" <<'EOF'
#!/bin/sh
exec /opt/gitopen/gitopen "$@"
EOF
chmod 0755 "${PKG_DIR}/usr/bin/gitopen"

cat > "${PKG_DIR}/usr/share/applications/gitopen.desktop" <<EOF
[Desktop Entry]
Name=GitOpen
Comment=Cross-platform desktop git client
Exec=/opt/gitopen/gitopen %U
Icon=gitopen
Type=Application
Categories=Development;RevisionControl;
Terminal=false
EOF

# Compute installed size in KB so dpkg shows it in `apt show`.
INSTALLED_SIZE=$(du -sk "${PKG_DIR}/opt" "${PKG_DIR}/usr" | awk '{s+=$1} END {print s}')

cat > "${PKG_DIR}/DEBIAN/control" <<EOF
Package: gitopen
Version: ${VERSION}
Section: devel
Priority: optional
Architecture: amd64
Installed-Size: ${INSTALLED_SIZE}
Depends: libgtk-3-0, libstdc++6, libc6, git
Maintainer: s.porta & zN3utr4l <zN3utr4l@users.noreply.github.com>
Homepage: https://github.com/zN3utr4l/GitOpen
Description: Cross-platform desktop git client
 GitOpen is a fast, native desktop git client built with Flutter.
 It wraps the system git CLI for all operations and provides a graph
 view, branch and remote management, conflict resolution UI, and
 chromeless window styling.
EOF

dpkg-deb --build --root-owner-group "${PKG_DIR}" "${OUT}"
echo "Built ${OUT}"
