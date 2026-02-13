use rust_lib_burrow_app::api::error::BurrowError;
use rust_lib_burrow_app::api::state;

#[tokio::test]
async fn state_not_initialized_after_destroy() {
    state::destroy_state().await;
    assert!(!state::is_initialized().await);
}

#[tokio::test]
async fn with_state_errors_when_not_initialized() {
    state::destroy_state().await;
    let result: Result<i32, BurrowError> = state::with_state(|_s| Ok(42)).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("not initialized"));
}

#[tokio::test]
async fn with_state_mut_errors_when_not_initialized() {
    state::destroy_state().await;
    let result: Result<i32, BurrowError> = state::with_state_mut(|_s| Ok(42)).await;
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("not initialized"));
}

#[tokio::test]
async fn init_and_use_state() {
    state::destroy_state().await;
    let keys = nostr_sdk::prelude::Keys::generate();
    let pubkey_hex = keys.public_key().to_hex();

    let _: () = state::init_state(keys).await.unwrap();
    assert!(state::is_initialized().await);

    let result: Result<String, BurrowError> =
        state::with_state(|s| Ok(s.keys.public_key().to_hex())).await;
    assert_eq!(result.unwrap(), pubkey_hex);

    state::destroy_state().await;
    assert!(!state::is_initialized().await);
}

#[tokio::test]
async fn destroy_then_reinit() {
    state::destroy_state().await;

    let keys1 = nostr_sdk::prelude::Keys::generate();
    let _: () = state::init_state(keys1).await.unwrap();
    let pk1: String = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await.unwrap();

    state::destroy_state().await;

    let keys2 = nostr_sdk::prelude::Keys::generate();
    let _: () = state::init_state(keys2).await.unwrap();
    let pk2: String = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await.unwrap();

    assert_ne!(pk1, pk2);
    state::destroy_state().await;
}
