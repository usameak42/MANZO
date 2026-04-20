// placeholder stubs — real implementation below in GREEN phase

// ---------------------------------------------------------------------------
// Unit tests — cargo test must pass
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_play_returns_zero() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_play stub must return 0");
    }

    #[test]
    fn stub_seek_returns_zero() {
        let result = manzo_seek(std::ptr::null_mut(), 1000);
        assert_eq!(result, 0, "manzo_seek stub must return 0");
    }

    #[test]
    fn stub_get_position_returns_zero() {
        let result = manzo_get_position(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_get_position stub must return 0");
    }

    #[test]
    fn stub_get_spectrum_returns_count() {
        let result = manzo_get_spectrum(std::ptr::null_mut(), std::ptr::null_mut(), 512);
        assert_eq!(result, 512, "manzo_get_spectrum stub must echo count");
    }
}
