uniffi::include_scaffolding!("hdri_encoder");

pub fn encoder_version() -> String {
    env!("CARGO_PKG_VERSION").to_owned()
}

pub fn target_output_format() -> String {
    "OpenEXR (.exr), 32-bit float equirectangular".to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposes_phase_one_metadata() {
        assert_eq!(encoder_version(), "0.1.0");
        assert!(target_output_format().contains(".exr"));
    }
}

