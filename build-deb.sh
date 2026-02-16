#!/bin/bash
set -euo pipefail

VERSION="1.0.0"
ARCH="amd64"
PKG_NAME="burrow"
DEB_NAME="${PKG_NAME}_${VERSION}_${ARCH}.deb"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
BUILD_DIR="$SCRIPT_DIR/build-deb-staging"
BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"

echo "==> Building Flutter Linux release..."
cd "$APP_DIR"
flutter build linux --release

echo "==> Preparing .deb staging directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/opt/burrow"
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/applications"

# Install icons at all standard hicolor sizes
for size in 16 24 32 48 64 128 256 512; do
    mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
    cp "$APP_DIR/linux/icons/${size}x${size}/burrow.png" \
       "$BUILD_DIR/usr/share/icons/hicolor/${size}x${size}/apps/burrow.png"
done

# Copy the full bundle
cp -r "$BUNDLE_DIR"/* "$BUILD_DIR/opt/burrow/"

# Symlink executable
ln -sf /opt/burrow/burrow_app "$BUILD_DIR/usr/bin/burrow"

# Desktop file
cp "$APP_DIR/linux/com.centauri.burrow_app.desktop" "$BUILD_DIR/usr/share/applications/com.centauri.burrow_app.desktop"

# DEBIAN/control
cat > "$BUILD_DIR/DEBIAN/control" <<EOF
Package: $PKG_NAME
Version: $VERSION
Section: net
Priority: optional
Architecture: $ARCH
Depends: libgtk-3-0, libglib2.0-0, libdbus-1-3
Maintainer: Burrow Team
Description: Burrow - Encrypted Messaging
 Secure, encrypted messaging app using the Marmot Protocol
 with MLS (Messaging Layer Security) and Nostr.
EOF

# DEBIAN/postinst - update icon cache after install
cat > "$BUILD_DIR/DEBIAN/postinst" <<'EOF'
#!/bin/bash
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postinst"

# DEBIAN/postrm - update icon cache after uninstall
cat > "$BUILD_DIR/DEBIAN/postrm" <<'EOF'
#!/bin/bash
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
fi
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database /usr/share/applications 2>/dev/null || true
fi
EOF
chmod 755 "$BUILD_DIR/DEBIAN/postrm"

echo "==> Building .deb package..."
dpkg-deb --build "$BUILD_DIR" "$SCRIPT_DIR/$DEB_NAME"

rm -rf "$BUILD_DIR"

echo "==> Built: $SCRIPT_DIR/$DEB_NAME"
echo "==> Install with: sudo dpkg -i $DEB_NAME"
