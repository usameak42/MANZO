use std::env;
use std::path::PathBuf;

fn main() {
    let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
    let out_dir = PathBuf::from(&crate_dir);

    cbindgen::Builder::new()
        .with_crate(&crate_dir)
        .with_config(cbindgen::Config::from_file(
            out_dir.join("cbindgen.toml"),
        ).expect("cbindgen.toml not found"))
        .generate()
        .expect("cbindgen generation failed")
        .write_to_file(out_dir.join("manzo_core.h"));
}
