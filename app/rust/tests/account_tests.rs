use nostr_sdk::prelude::ToBech32;
use rust_lib_burrow_app::api::error::BurrowError;
use rust_lib_burrow_app::api::{account, state};

/// Set up a temporary data directory for tests that need init_state.
fn setup_test_data_dir() {
    let tmp = std::env::temp_dir().join("burrow_tests");
    std::fs::create_dir_all(&tmp).unwrap();
    state::set_data_dir(tmp.to_string_lossy().to_string());
}

#[tokio::test]
async fn create_account_initializes_state() {
    state::destroy_state().await;
    setup_test_data_dir();

    let info: account::AccountInfo = account::create_account().await.unwrap();
    assert!(!info.pubkey_hex.is_empty());
    assert!(info.npub.starts_with("npub1"));
    assert_eq!(info.pubkey_hex.len(), 64);
    assert!(account::is_logged_in().await);

    state::destroy_state().await;
}

#[tokio::test]
async fn logout_destroys_state() {
    state::destroy_state().await;
    setup_test_data_dir();

    let _: account::AccountInfo = account::create_account().await.unwrap();
    assert!(account::is_logged_in().await);

    let _: () = account::logout().await.unwrap();
    assert!(!account::is_logged_in().await);
}

#[tokio::test]
async fn get_current_account_after_create() {
    state::destroy_state().await;
    setup_test_data_dir();

    let created: account::AccountInfo = account::create_account().await.unwrap();
    let current: account::AccountInfo = account::get_current_account().await.unwrap();
    assert_eq!(created.pubkey_hex, current.pubkey_hex);
    assert_eq!(created.npub, current.npub);

    state::destroy_state().await;
}

#[tokio::test]
async fn get_current_account_when_not_logged_in() {
    state::destroy_state().await;

    let result: Result<account::AccountInfo, BurrowError> = account::get_current_account().await;
    assert!(result.is_err());
}

#[tokio::test]
async fn login_with_invalid_key_fails() {
    state::destroy_state().await;

    let result: Result<account::AccountInfo, BurrowError> =
        account::login("not_a_valid_key".to_string()).await;
    assert!(result.is_err());
}

#[tokio::test]
async fn login_with_hex_secret_key() {
    state::destroy_state().await;
    setup_test_data_dir();

    let keys = nostr_sdk::prelude::Keys::generate();
    let hex_secret = keys.secret_key().to_secret_hex();
    let expected_pubkey = keys.public_key().to_hex();

    let info: account::AccountInfo = account::login(hex_secret).await.unwrap();
    assert_eq!(info.pubkey_hex, expected_pubkey);

    state::destroy_state().await;
}

#[tokio::test]
async fn login_with_nsec_key() {
    state::destroy_state().await;
    setup_test_data_dir();

    let keys = nostr_sdk::prelude::Keys::generate();
    let nsec = keys.secret_key().to_bech32().unwrap();
    let expected_pubkey = keys.public_key().to_hex();

    let info: account::AccountInfo = account::login(nsec).await.unwrap();
    assert_eq!(info.pubkey_hex, expected_pubkey);

    state::destroy_state().await;
}

// Note: save/load via keyring requires platform-specific keyring backends
// and cannot be reliably tested in a headless CI environment.
