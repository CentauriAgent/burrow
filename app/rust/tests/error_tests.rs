use rust_lib_burrow_app::api::error::BurrowError;

#[test]
fn error_from_string() {
    let err = BurrowError::from("test error".to_string());
    assert_eq!(err.message, "test error");
}

#[test]
fn error_display() {
    let err = BurrowError { message: "display test".to_string() };
    assert_eq!(format!("{}", err), "display test");
}

#[test]
fn error_debug() {
    let err = BurrowError { message: "debug test".to_string() };
    let debug = format!("{:?}", err);
    assert!(debug.contains("debug test"));
}

#[test]
fn error_from_io_error() {
    let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
    let err = BurrowError::from(io_err);
    assert!(err.message.contains("file not found"));
}

#[test]
fn error_clone() {
    let err = BurrowError { message: "clone me".to_string() };
    let cloned = err.clone();
    assert_eq!(err.message, cloned.message);
}

#[test]
fn error_from_anyhow() {
    let anyhow_err = anyhow::anyhow!("anyhow error");
    let err = BurrowError::from(anyhow_err);
    assert_eq!(err.message, "anyhow error");
}

#[test]
fn error_empty_message() {
    let err = BurrowError::from(String::new());
    assert_eq!(err.message, "");
    assert_eq!(format!("{}", err), "");
}

#[test]
fn error_unicode_message() {
    let err = BurrowError::from("错误 🔑".to_string());
    assert_eq!(err.message, "错误 🔑");
}
