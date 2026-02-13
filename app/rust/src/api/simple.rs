/// A simple greeting function to verify the FFI bridge works.
#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}! Welcome to Burrow 🦫")
}

/// Returns the current version of the Rust core library.
#[flutter_rust_bridge::frb(sync)]
pub fn rust_lib_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Initialize the Burrow core (placeholder for future MLS/Nostr setup).
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
