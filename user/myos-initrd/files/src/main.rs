use std::ffi::{CString, c_char, c_int, c_ulong, c_void};
use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

const MS_RDONLY: c_ulong = 1;
const MS_NOSUID: c_ulong = 2;
const MS_NODEV: c_ulong = 4;
const MS_NOEXEC: c_ulong = 8;
const MS_MOVE: c_ulong = 8192;
const MS_REC: c_ulong = 16384;
const MS_PRIVATE: c_ulong = 1 << 18;
unsafe extern "C" {
    fn mount(
        source: *const c_char,
        target: *const c_char,
        filesystemtype: *const c_char,
        mountflags: c_ulong,
        data: *const c_void,
    ) -> c_int;
    fn chdir(path: *const c_char) -> c_int;
    fn chroot(path: *const c_char) -> c_int;
}

#[derive(Debug, PartialEq, Eq)]
struct BootConfig {
    root: String,
    root_type: Option<String>,
    root_flags: String,
    readonly: bool,
    wait_forever: bool,
    delay: u64,
    timeout: u64,
    init: String,
    shell_on_error: bool,
}

impl Default for BootConfig {
    fn default() -> Self {
        Self {
            root: String::new(),
            root_type: None,
            root_flags: String::new(),
            readonly: false,
            wait_forever: false,
            delay: 0,
            timeout: 30,
            init: "/usr/bin/dinit".into(),
            shell_on_error: true,
        }
    }
}

fn parse_cmdline(line: &str) -> BootConfig {
    let mut cfg = BootConfig::default();
    for token in line.split_ascii_whitespace() {
        if token == "ro" {
            cfg.readonly = true;
        } else if token == "rw" {
            cfg.readonly = false;
        } else if token == "rootwait" {
            cfg.wait_forever = true;
        } else if token == "rd.shell=0" {
            cfg.shell_on_error = false;
        } else if let Some(value) = token.strip_prefix("root=") {
            cfg.root = value.into();
        } else if let Some(value) = token.strip_prefix("rootfstype=") {
            cfg.root_type = Some(value.into());
        } else if let Some(value) = token.strip_prefix("rootflags=") {
            cfg.root_flags = value.into();
        } else if let Some(value) = token.strip_prefix("rootdelay=") {
            cfg.delay = value.parse().unwrap_or(0);
        } else if let Some(value) = token.strip_prefix("rd.timeout=") {
            cfg.timeout = value.parse().unwrap_or(30);
        } else if let Some(value) = token.strip_prefix("init=") {
            if value.starts_with('/') {
                cfg.init = value.into();
            }
        }
    }
    cfg
}

fn cstring(value: &str) -> Result<CString, String> {
    CString::new(value).map_err(|_| format!("invalid NUL byte in {value:?}"))
}

fn mount_fs(
    source: Option<&str>,
    target: &str,
    fs_type: Option<&str>,
    flags: c_ulong,
    data: Option<&str>,
) -> Result<(), String> {
    let source = source.map(cstring).transpose()?;
    let target = cstring(target)?;
    let fs_type = fs_type.map(cstring).transpose()?;
    let data = data.map(cstring).transpose()?;
    // SAFETY: all non-null pointers refer to live, NUL-terminated C strings.
    let rc = unsafe {
        mount(
            source.as_ref().map_or(std::ptr::null(), |v| v.as_ptr()),
            target.as_ptr(),
            fs_type.as_ref().map_or(std::ptr::null(), |v| v.as_ptr()),
            flags,
            data.as_ref()
                .map_or(std::ptr::null(), |v| v.as_ptr().cast()),
        )
    };
    if rc == 0 {
        Ok(())
    } else {
        Err(format!(
            "mount {target:?}: {}",
            std::io::Error::last_os_error()
        ))
    }
}

fn prepare_kernel_filesystems() -> Result<(), String> {
    for path in ["/dev", "/proc", "/sys", "/run", "/newroot"] {
        fs::create_dir_all(path).map_err(|e| format!("mkdir {path}: {e}"))?;
    }
    mount_fs(None, "/", None, MS_REC | MS_PRIVATE, None)?;
    mount_fs(
        Some("devtmpfs"),
        "/dev",
        Some("devtmpfs"),
        MS_NOSUID,
        Some("mode=0755"),
    )?;
    // Mounting devtmpfs hides children created below the old /dev.
    fs::create_dir_all("/dev/pts").map_err(|e| format!("mkdir /dev/pts: {e}"))?;
    mount_fs(
        Some("devpts"),
        "/dev/pts",
        Some("devpts"),
        MS_NOSUID | MS_NOEXEC,
        None,
    )?;
    mount_fs(
        Some("proc"),
        "/proc",
        Some("proc"),
        MS_NOSUID | MS_NODEV | MS_NOEXEC,
        None,
    )?;
    mount_fs(
        Some("sysfs"),
        "/sys",
        Some("sysfs"),
        MS_NOSUID | MS_NODEV | MS_NOEXEC,
        None,
    )?;
    mount_fs(
        Some("tmpfs"),
        "/run",
        Some("tmpfs"),
        MS_NOSUID | MS_NODEV,
        Some("mode=0755"),
    )?;
    Ok(())
}

fn load_modules() -> Result<(), String> {
    let module_list = match fs::read_to_string("/etc/modules.load") {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(format!("read /etc/modules.load: {error}")),
    };
    for line in module_list.lines() {
        let module = line.trim();
        if module.is_empty() || module.starts_with('#') {
            continue;
        }
        let status = Command::new("/bin/armybox")
            .arg("insmod")
            .arg(module)
            .status()
            .map_err(|e| format!("start insmod for {module}: {e}"))?;
        if !status.success() {
            return Err(format!("insmod failed for {module}: {status}"));
        }
        eprintln!("myos-initrd: loaded {module}");
    }
    Ok(())
}

fn root_path(spec: &str) -> PathBuf {
    for (prefix, directory) in [
        ("UUID=", "/dev/disk/by-uuid"),
        ("PARTUUID=", "/dev/disk/by-partuuid"),
        ("LABEL=", "/dev/disk/by-label"),
        ("PARTLABEL=", "/dev/disk/by-partlabel"),
    ] {
        if let Some(value) = spec.strip_prefix(prefix) {
            return Path::new(directory).join(value);
        }
    }
    PathBuf::from(spec)
}

fn wait_for_root(cfg: &BootConfig) -> Result<PathBuf, String> {
    if cfg.root.is_empty() {
        return Err("kernel command line has no root= device".into());
    }
    if cfg.delay > 0 {
        thread::sleep(Duration::from_secs(cfg.delay));
    }
    let path = root_path(&cfg.root);
    let start = Instant::now();
    loop {
        if path.exists() {
            return Ok(path);
        }
        if !cfg.wait_forever && start.elapsed() >= Duration::from_secs(cfg.timeout) {
            return Err(format!("root device {} did not appear", path.display()));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

fn mount_root(device: &Path, cfg: &BootConfig) -> Result<(), String> {
    let device = device
        .to_str()
        .ok_or_else(|| "root device is not valid UTF-8".to_string())?;
    let flags = if cfg.readonly { MS_RDONLY } else { 0 };
    let candidates: Vec<&str> = cfg
        .root_type
        .as_deref()
        .map(|kind| vec![kind])
        .unwrap_or_else(|| vec!["ext4", "xfs", "btrfs", "f2fs", "squashfs"]);
    let mut errors = Vec::new();
    for kind in candidates {
        match mount_fs(
            Some(device),
            "/newroot",
            Some(kind),
            flags,
            (!cfg.root_flags.is_empty()).then_some(cfg.root_flags.as_str()),
        ) {
            Ok(()) => return Ok(()),
            Err(error) => errors.push(format!("{kind}: {error}")),
        }
    }
    Err(format!(
        "cannot mount root device {device}: {}",
        errors.join("; ")
    ))
}

fn move_mount(old: &str, new: &str) -> Result<(), String> {
    fs::create_dir_all(new).map_err(|e| format!("mkdir {new}: {e}"))?;
    mount_fs(Some(old), new, None, MS_MOVE, None)
}

fn switch_root(init: &str) -> Result<(), String> {
    for name in ["dev", "proc", "sys", "run"] {
        move_mount(&format!("/{name}"), &format!("/newroot/{name}"))?;
    }
    let newroot = cstring("/newroot")?;
    // SAFETY: newroot is a valid C string and the return value is checked.
    if unsafe { chdir(newroot.as_ptr()) } != 0 {
        return Err(format!(
            "chdir newroot: {}",
            std::io::Error::last_os_error()
        ));
    }
    let dot = cstring(".")?;
    // The initramfs root is the kernel's special rootfs and cannot be passed
    // to pivot_root(2). Move the mounted real root over /, then confine PID 1
    // to it with chroot(2), which is the switch_root pattern for initramfs.
    mount_fs(Some("."), "/", None, MS_MOVE, None)?;
    // SAFETY: dot is a valid C string and the return value is checked.
    if unsafe { chroot(dot.as_ptr()) } != 0 {
        return Err(format!("chroot: {}", std::io::Error::last_os_error()));
    }
    let slash = cstring("/")?;
    // SAFETY: slash is a valid C string.
    if unsafe { chdir(slash.as_ptr()) } != 0 {
        return Err(format!("chdir /: {}", std::io::Error::last_os_error()));
    }
    let error = Command::new(init).exec();
    Err(format!("exec {init}: {error}"))
}

fn emergency_shell(message: &str, enabled: bool) -> ! {
    eprintln!("myos-initrd: {message}");
    if !enabled {
        loop {
            thread::park();
        }
    }
    loop {
        eprintln!("myos-initrd: starting Armybox recovery shell");
        match Command::new("/bin/armybox").arg("sh").status() {
            Ok(status) => eprintln!("myos-initrd: shell exited with {status}"),
            Err(error) => eprintln!("myos-initrd: cannot start shell: {error}"),
        }
        thread::sleep(Duration::from_secs(1));
    }
}

fn boot() -> Result<(), String> {
    prepare_kernel_filesystems()?;
    load_modules()?;
    let cmdline = fs::read_to_string("/proc/cmdline").map_err(|e| format!("read cmdline: {e}"))?;
    let cfg = parse_cmdline(&cmdline);
    let root = wait_for_root(&cfg)?;
    mount_root(&root, &cfg)?;
    switch_root(&cfg.init)
}

fn main() {
    if std::env::args().any(|arg| arg == "--self-test") {
        println!("myos-initrd 0.1.0");
        return;
    }
    if std::process::id() != 1 {
        eprintln!("myos-initrd: must run as PID 1 (use --self-test for a host check)");
        std::process::exit(2);
    }
    if let Err(error) = boot() {
        let cmdline = fs::read_to_string("/proc/cmdline").unwrap_or_default();
        emergency_shell(&error, parse_cmdline(&cmdline).shell_on_error);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_boot_contract() {
        let cfg = parse_cmdline(
            "quiet root=PARTUUID=abcd rootfstype=ext4 rootflags=noatime ro rootwait rootdelay=2 init=/usr/bin/dinit",
        );
        assert_eq!(cfg.root, "PARTUUID=abcd");
        assert_eq!(cfg.root_type.as_deref(), Some("ext4"));
        assert_eq!(cfg.root_flags, "noatime");
        assert!(cfg.readonly && cfg.wait_forever);
        assert_eq!(cfg.delay, 2);
        assert_eq!(cfg.init, "/usr/bin/dinit");
    }

    #[test]
    fn maps_stable_device_aliases() {
        assert_eq!(
            root_path("UUID=123"),
            PathBuf::from("/dev/disk/by-uuid/123")
        );
        assert_eq!(root_path("/dev/vda2"), PathBuf::from("/dev/vda2"));
    }

    #[test]
    fn rejects_relative_init() {
        assert_eq!(parse_cmdline("init=bin/sh").init, "/usr/bin/dinit");
    }
}
