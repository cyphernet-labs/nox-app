//! How an event reaches Dart: a message posted to a port of the isolate that
//! opened the channel.
//!
//! A port, not a function of the isolate's. A function `NativeCallable` makes
//! is deleted with its isolate, and the VM aborts the whole process on the next
//! call into it - while the channels of this module outlive any isolate: a hot
//! restart, or an engine Android tears down on Back, leaves them running in the
//! same process. A post to a port whose isolate is gone is only refused, and
//! the channel then ends itself (`registry`).
//!
//! The function that posts is `Dart_PostCObject`, which Dart hands over as
//! `NativeApi.postCObject`: it may be called from any thread, and it copies the
//! message before it returns.

use std::ffi::c_void;

/// `Dart_CObject_kTypedData` (dart_native_api.h): the one kind posted here.
const TYPED_DATA: i32 = 7;

/// `Dart_TypedData_kUint8` (dart_api.h): the message arrives as a `Uint8List`.
const UINT8: i32 = 2;

/// What every event message starts with, in this machine's byte order: the
/// handle (8 bytes), the kind (4) and the code (4). The bytes of an OPEN or a
/// DATA follow.
pub const HEADER: usize = 16;

/// `Dart_CObject` (dart_native_api.h): the members read here, and the largest
/// one, so the struct is as large as the one Dart reads.
#[repr(C)]
pub struct DartCObject {
    pub ty: i32,
    pub value: DartCObjectValue,
}

#[repr(C)]
pub union DartCObjectValue {
    pub as_typed_data: TypedData,
    as_int64: i64,
    as_external_typed_data: ExternalTypedData,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TypedData {
    pub ty: i32,
    /// In elements: in bytes, for a `Uint8List`.
    pub length: isize,
    pub values: *const u8,
}

#[repr(C)]
#[derive(Clone, Copy)]
struct ExternalTypedData {
    ty: i32,
    length: isize,
    data: *mut u8,
    peer: *mut c_void,
    callback: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
}

/// `Dart_PostCObject`: non-zero when the port took the message.
pub type PostFn = unsafe extern "C" fn(port: i64, message: *mut DartCObject) -> i8;

/// Where the events of one channel go: a port of the isolate that opened it.
#[derive(Clone, Copy)]
pub struct Port {
    post: PostFn,
    id: i64,
}

impl Port {
    pub fn new(post: PostFn, id: i64) -> Self {
        Port { post, id }
    }

    /// Posts one event. False when the port took nothing: its isolate is gone.
    pub fn post(&self, handle: i64, kind: i32, code: i32, data: &[u8]) -> bool {
        let mut message = Vec::with_capacity(HEADER + data.len());
        message.extend_from_slice(&handle.to_ne_bytes());
        message.extend_from_slice(&kind.to_ne_bytes());
        message.extend_from_slice(&code.to_ne_bytes());
        message.extend_from_slice(data);
        let mut object = DartCObject {
            ty: TYPED_DATA,
            value: DartCObjectValue {
                as_typed_data: TypedData { ty: UINT8, length: message.len() as isize, values: message.as_ptr() },
            },
        };
        // Copied into Dart's message before the call returns: `message` may go.
        unsafe { (self.post)(self.id, &mut object) != 0 }
    }
}

/// One event message read back - (handle, kind, code, bytes) - the way Dart
/// reads it; for the module's own tests, which stand in for Dart. None for
/// anything the module would not post.
///
/// # Safety
/// `message` points at a `DartCObject` whose typed data, if any, is readable.
#[doc(hidden)]
pub unsafe fn decode(message: *const DartCObject) -> Option<(i64, i32, i32, Vec<u8>)> {
    let message = message.as_ref()?;
    if message.ty != TYPED_DATA {
        return None;
    }
    let data = message.value.as_typed_data;
    if data.ty != UINT8 || data.values.is_null() || data.length < HEADER as isize {
        return None;
    }
    let bytes = std::slice::from_raw_parts(data.values, data.length as usize);
    let handle = i64::from_ne_bytes(bytes[0..8].try_into().ok()?);
    let kind = i32::from_ne_bytes(bytes[8..12].try_into().ok()?);
    let code = i32::from_ne_bytes(bytes[12..16].try_into().ok()?);
    Some((handle, kind, code, bytes[HEADER..].to_vec()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[cfg(target_pointer_width = "64")]
    fn the_struct_is_laid_out_as_darts() {
        // dart_native_api.h on a 64-bit target: the type, then at 8 a union
        // whose largest member, the external typed data, takes five words.
        assert_eq!(std::mem::size_of::<DartCObject>(), 48);
        assert_eq!(std::mem::offset_of!(DartCObject, value), 8);
        assert_eq!(std::mem::offset_of!(TypedData, length), 8);
        assert_eq!(std::mem::offset_of!(TypedData, values), 16);
    }

    unsafe extern "C" fn echo(port: i64, message: *mut DartCObject) -> i8 {
        let decoded = decode(message).unwrap();
        assert_eq!(port, 42);
        assert_eq!(decoded, (7, 2, -3, b"bytes".to_vec()));
        1
    }

    unsafe extern "C" fn refuse(_: i64, _: *mut DartCObject) -> i8 {
        0
    }

    #[test]
    fn an_event_goes_out_as_one_uint8list_and_a_refusal_is_reported() {
        assert!(Port::new(echo, 42).post(7, 2, -3, b"bytes"));
        assert!(!Port::new(refuse, 42).post(7, 2, -3, b"bytes"));
    }
}
