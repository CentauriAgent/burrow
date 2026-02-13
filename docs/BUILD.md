# Build Guide

Detailed instructions for building Burrow on every supported platform.

## Prerequisites (All Platforms)

1. **Flutter SDK** ≥ 3.11 — [Install Flutter](https://docs.flutter.dev/get-started/install)
2. **Rust toolchain** (stable) — [Install Rust](https://rustup.rs/)
3. **Git** — to clone the repo

```bash
# Verify installations
flutter --version   # Should show ≥ 3.11
rustc --version     # Should show stable
cargo --version
```

## Clone & Setup

```bash
git clone https://github.com/CentauriAgent/burrow.git
cd burrow/app

# Install Flutter dependencies
flutter pub get

# Generate flutter_rust_bridge bindings (required after Rust API changes)
flutter_rust_bridge_codegen generate
```

---

## Android

### Additional Prerequisites
- **Android Studio** with Android SDK
- **Android NDK** (installed via Android Studio → SDK Manager → SDK Tools → NDK)
- **cargo-ndk** — cross-compile Rust for Android

```bash
# Install cargo-ndk
cargo install cargo-ndk

# Add Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
```

### Build

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release
```

### Run on Device/Emulator

```bash
# List available devices
flutter devices

# Run on connected Android device
flutter run -d <device-id>
```

### Troubleshooting
- If NDK is not found, set `ANDROID_NDK_HOME` environment variable
- Minimum SDK version: check `android/app/build.gradle` for `minSdkVersion`
- Cargokit handles the Rust cross-compilation automatically via Gradle integration

---

## iOS

### Additional Prerequisites
- **macOS** (required)
- **Xcode** ≥ 15 with iOS SDK
- **CocoaPods** — `sudo gem install cocoapods`

```bash
# Add iOS target
rustup target add aarch64-apple-ios

# For simulator (Apple Silicon)
rustup target add aarch64-apple-ios-sim

# For simulator (Intel)
rustup target add x86_64-apple-ios
```

### Build

```bash
cd burrow/app

# Install CocoaPods dependencies
cd ios && pod install && cd ..

# Debug build
flutter build ios --debug --no-codesign

# Release build (requires signing)
flutter build ios --release
```

### Run on Simulator

```bash
# Open iOS simulator
open -a Simulator

# Run
flutter run -d <simulator-id>
```

### Signing
For release builds, configure signing in Xcode:
1. Open `ios/Runner.xcworkspace` in Xcode
2. Select the Runner target → Signing & Capabilities
3. Set your Team and Bundle Identifier

---

## Linux

### Additional Prerequisites
```bash
# Ubuntu/Debian
sudo apt-get install clang cmake git ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

### Build

```bash
# Debug
flutter build linux --debug

# Release
flutter build linux --release
```

Output: `build/linux/x64/release/bundle/`

### Run

```bash
flutter run -d linux
```

---

## macOS

### Additional Prerequisites
- **Xcode** ≥ 15 with macOS SDK
- **CocoaPods** — `sudo gem install cocoapods`

```bash
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

### Build

```bash
cd ios && pod install && cd ..  # if using CocoaPods for macOS

# Debug
flutter build macos --debug

# Release
flutter build macos --release
```

Output: `build/macos/Build/Products/Release/`

### Run

```bash
flutter run -d macos
```

---

## Windows

### Additional Prerequisites
- **Visual Studio 2022** with "Desktop development with C++" workload
- **Windows 10 SDK**

```bash
rustup target add x86_64-pc-windows-msvc
```

### Build

```powershell
# Debug
flutter build windows --debug

# Release
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\`

### Run

```powershell
flutter run -d windows
```

---

## Development Mode

```bash
cd burrow/app

# Hot-reload development on any connected device
flutter run -d <device>

# Run with verbose logging
flutter run -d <device> --verbose

# Run Dart tests
flutter test

# Run Rust tests
cd rust && cargo test

# Run integration tests
flutter test integration_test/

# Dart analysis
flutter analyze

# Rust lints
cd rust && cargo clippy -- -D warnings
```

## Regenerating Rust Bridge Bindings

After modifying any Rust function signatures in `app/rust/src/api/`:

```bash
cd burrow/app
flutter_rust_bridge_codegen generate
```

This regenerates the Dart FFI bindings in `lib/src/rust/`.

---

## CLI (Phase 1)

The TypeScript CLI has simpler requirements:

```bash
cd burrow
npm install
npm run build
npx burrow --help
```

Requirements: Node.js ≥ 20, npm ≥ 9.
