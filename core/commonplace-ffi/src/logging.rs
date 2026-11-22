//! Platform logging. Neither backend opens a network connection.

pub fn init() {
    #[cfg(target_os = "android")]
    android_logger::init_once(android_logger::Config::default().with_max_level(log::LevelFilter::Info).with_tag("commonplace"));

    #[cfg(target_vendor = "apple")]
    {
        static INIT: std::sync::Once = std::sync::Once::new();
        INIT.call_once(|| {
            // An embedding application may have installed its own logger already.
            static LOGGER: std::sync::OnceLock<AppleLogger> = std::sync::OnceLock::new();
            if log::set_logger(LOGGER.get_or_init(|| AppleLogger(oslog::OsLog::new("app.commonplace", "core")))).is_ok() {
                log::set_max_level(log::LevelFilter::Warn);
            }
        });
    }
}

#[cfg(target_vendor = "apple")]
struct AppleLogger(oslog::OsLog);

#[cfg(target_vendor = "apple")]
impl log::Log for AppleLogger {
    fn enabled(&self, metadata: &log::Metadata<'_>) -> bool {
        metadata.level() <= log::Level::Warn
    }

    fn log(&self, record: &log::Record<'_>) {
        if self.enabled(record.metadata()) {
            // The runtime can include paths in errors; never log questions, answers or evidence here.
            self.0.with_level(if record.level() == log::Level::Error { oslog::Level::Error } else { oslog::Level::Default }, &record.args().to_string());
        }
    }

    fn flush(&self) {}
}
