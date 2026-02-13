use flutter_rust_bridge::frb;

/// API error type that bridges to Flutter as a simple string.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct BurrowError {
    pub message: String,
}

impl std::fmt::Display for BurrowError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl From<anyhow::Error> for BurrowError {
    fn from(e: anyhow::Error) -> Self {
        Self {
            message: e.to_string(),
        }
    }
}

impl From<nostr_sdk::prelude::Error> for BurrowError {
    fn from(e: nostr_sdk::prelude::Error) -> Self {
        Self {
            message: e.to_string(),
        }
    }
}

impl From<mdk_core::Error> for BurrowError {
    fn from(e: mdk_core::Error) -> Self {
        Self {
            message: e.to_string(),
        }
    }
}

impl From<String> for BurrowError {
    fn from(s: String) -> Self {
        Self { message: s }
    }
}

impl From<std::io::Error> for BurrowError {
    fn from(e: std::io::Error) -> Self {
        Self {
            message: e.to_string(),
        }
    }
}
