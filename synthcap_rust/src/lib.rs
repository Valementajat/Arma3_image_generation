use std::fs::{create_dir_all, File, OpenOptions};
use std::io::{BufWriter, Write};
use std::path::Path;
use std::sync::Mutex;
//
use std::sync::atomic::{AtomicBool, Ordering};

use arma_rs::{arma, Extension};

static SINK: Mutex<Option<BufWriter<File>>> = Mutex::new(None);
//
static RUNNING: AtomicBool = AtomicBool::new(false);

fn version() -> String {
    format!("synthcap {}", env!("CARGO_PKG_VERSION"))
}

fn open(path: String) -> String {
    let p = Path::new(&path);
    if let Some(dir) = p.parent() {
        if let Err(e) = create_dir_all(dir) {
            return format!("err:mkdir:{e}");
        }
    }
    match OpenOptions::new().create(true).append(true).open(p) {
        Ok(f) => {
            *SINK.lock().unwrap() = Some(BufWriter::with_capacity(1 << 16, f));
            "ok".into()
        }
        Err(e) => format!("err:open:{e}"),
    }
}

fn write(line: String) -> String {
    let mut guard = SINK.lock().unwrap();
    match guard.as_mut() {
        Some(w) => match writeln!(w, "{line}") {
            Ok(_) => "ok".into(),
            Err(e) => format!("err:write:{e}"),
        },
        None => "err:not_open".into(),
    }
}

fn flush() -> String {
    let mut guard = SINK.lock().unwrap();
    match guard.as_mut() {
        Some(w) => match w.flush() {
            Ok(_) => "ok".into(),
            Err(e) => format!("err:flush:{e}"),
        },
        None => "err:not_open".into(),
    }
}

fn close() -> String {
    let mut guard = SINK.lock().unwrap();
    if let Some(mut w) = guard.take() {
        let _ = w.flush();
    }
    "ok".into()
}


fn exists(path: String) -> String {
    if Path::new(&path).exists() { "1".into() } else { "0".into() }
}

// spawn once; moves *.png from src to dst every 500 ms
fn sweep(src: String, dst: String) -> String {
    if RUNNING.swap(true, Ordering::SeqCst) { return "ok:already".into(); }
    std::thread::spawn(move || {
        let _ = create_dir_all(&dst);
        while RUNNING.load(Ordering::SeqCst) {
            if let Ok(rd) = std::fs::read_dir(&src) {
                for e in rd.flatten() {
                    let p = e.path();
                    if p.extension().map_or(false, |x| x == "png") {
                        if let Some(n) = p.file_name() {
                            let _ = std::fs::rename(&p, Path::new(&dst).join(n));
                        }
                    }
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(500));
        }
    });
    "ok".into()
}

fn shutdown() -> String { let _ = close(); std::process::exit(0); }




#[arma]
fn init() -> Extension {
    Extension::build()
        .command("version", version)
        .command("open", open)
        .command("write", write)
        .command("flush", flush)
        .command("close", close)
        .command("exists", exists)
        .command("sweep", sweep)
        .command("shutdown", shutdown)
        .finish()
}