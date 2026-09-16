use std::thread;

use zbus::{blocking::Connection, interface};

const BUS_NAME: &str = "org.myos.System1";
const OBJECT_PATH: &str = "/org/myos/System1";

#[derive(Default)]
struct SystemService;

#[interface(name = "org.myos.System1")]
impl SystemService {
    fn ping(&self) -> &'static str {
        "pong"
    }

    #[zbus(property)]
    fn version(&self) -> &'static str {
        env!("CARGO_PKG_VERSION")
    }
}

fn serve() -> zbus::Result<()> {
    let connection = Connection::system()?;
    connection.object_server().at(OBJECT_PATH, SystemService)?;
    connection.request_name(BUS_NAME)?;
    loop {
        thread::park();
    }
}

fn main() {
    if std::env::args().any(|arg| arg == "--self-test") {
        println!("myos-system-bus {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    if let Err(error) = serve() {
        eprintln!("myos-system-bus: {error}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stable_identity() {
        assert_eq!(BUS_NAME, "org.myos.System1");
        assert_eq!(OBJECT_PATH, "/org/myos/System1");
        assert_eq!(SystemService.ping(), "pong");
    }
}
