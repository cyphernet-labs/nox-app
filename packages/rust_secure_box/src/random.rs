//! Where random bytes come from - the one thing RustSecureBox takes from
//! outside.
//!
//! In the app, from the system. In WebAssembly, from the host: the module
//! imports exactly one function, `env.rsb_random`, which the server's Go
//! wrapper answers from `crypto/rand`. Any other import would be an access to
//! the system the interface forbids, and the server's build refuses it: the Go
//! copy's import interface must hold that one method and nothing else.

use crate::Error;

/// Fills `buf` with random bytes.
pub(crate) fn fill(buf: &mut [u8]) -> Result<(), Error> {
    #[cfg(target_arch = "wasm32")]
    {
        #[link(wasm_import_module = "env")]
        extern "C" {
            /// 0 when `len` random bytes were written at `ptr`.
            fn rsb_random(ptr: *mut u8, len: u32) -> i32;
        }
        let len = u32::try_from(buf.len()).map_err(|_| Error::InvalidArgument)?;
        // SAFETY: the host writes exactly `len` bytes at `ptr`, which is the
        // start of `buf` - a live, exclusively borrowed slice of that length.
        if unsafe { rsb_random(buf.as_mut_ptr(), len) } == 0 {
            Ok(())
        } else {
            Err(Error::Random)
        }
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        getrandom::fill(buf).map_err(|_| Error::Random)
    }
}
