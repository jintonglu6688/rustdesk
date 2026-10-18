use hbb_common::config::DEFAULT_SETTINGS;

use super::keys;

pub fn initialize() {
    let mut settings = DEFAULT_SETTINGS.write().unwrap();
    for (key, value) in [
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, "r.jtl.world:21116"),
        (keys::OPTION_RELAY_SERVER, "r.jtl.world:21117"),
        (
            keys::OPTION_KEY,
            "4egOeXzPQuj9P5AEyilmAI0AI3t3MHYHMWWLRGZ7TY0=",
        ),
        (keys::OPTION_API_SERVER, ""),
        (keys::OPTION_ALLOW_WEBSOCKET, "N"),
    ] {
        settings
            .entry(key.to_owned())
            .or_insert_with(|| value.to_owned());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::config::{self, Config};

    #[test]
    fn new_client_uses_self_hosted_defaults_without_writing_user_configuration() {
        *config::APP_NAME.write().unwrap() =
            format!("RustDesk-ServerDefaults-{}", std::process::id());
        assert!(!config::Config2::file().exists());
        initialize();
        assert_eq!(
            Config::get_option(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER),
            "r.jtl.world:21116"
        );
        assert_eq!(
            Config::get_option(keys::OPTION_RELAY_SERVER),
            "r.jtl.world:21117"
        );
        assert_eq!(
            Config::get_option(keys::OPTION_KEY),
            "4egOeXzPQuj9P5AEyilmAI0AI3t3MHYHMWWLRGZ7TY0="
        );
        assert_eq!(Config::get_option(keys::OPTION_API_SERVER), "");
        assert!(!config::use_ws());
        assert!(!config::Config2::file().exists());
        // A verified custom client can provide more specific defaults later.
        DEFAULT_SETTINGS.write().unwrap().insert(
            keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(),
            "other.example:21116".to_owned(),
        );
        initialize();
        assert_eq!(
            Config::get_option(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER),
            "other.example:21116"
        );
    }
}
