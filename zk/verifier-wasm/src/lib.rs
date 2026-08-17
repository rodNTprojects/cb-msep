//! Vérifieur RISC Zero exposé comme module WASM "reactor" (brique B).
//!
//! ABI avec l'hôte Go/wazero (chaincode/verification/verifier_stark.go) :
//!   - `alloc(len) -> ptr`    : réserve un tampon dans la mémoire linéaire wasm.
//!   - `dealloc(ptr, len)`    : libère un tampon.
//!   - `verify(receipt_ptr, receipt_len, img_ptr, img_len) -> i32`
//!         0 = valide ; 1 = invalide ; 2 = décodage borsh échoué ; 3 = image id != 32.
//!   - `journal_ptr() / journal_len()` : après verify==0, exposent le journal
//!         (sorties publiques, dont l'engagement C) pour le lier à l'engagement signé.
//!
//! Receipt transmis en borsh (même format que la brique A). Image id en 32
//! octets bruts (= Digest::as_bytes côté host), reconstruit par Digest::from_bytes.

use borsh::BorshDeserialize;
use core::cell::UnsafeCell;
use risc0_zkvm::sha::Digest;
use risc0_zkvm::Receipt;

#[no_mangle]
pub extern "C" fn alloc(len: usize) -> *mut u8 {
    let mut buf: Vec<u8> = Vec::with_capacity(len);
    let ptr = buf.as_mut_ptr();
    core::mem::forget(buf);
    ptr
}

/// # Safety
/// `ptr`/`len` doivent provenir d'un appel `alloc` précédent.
#[no_mangle]
pub unsafe extern "C" fn dealloc(ptr: *mut u8, len: usize) {
    if !ptr.is_null() && len != 0 {
        let _ = Vec::from_raw_parts(ptr, 0, len);
    }
}

// Journal de la dernière vérification réussie.
// UnsafeCell dans un `static` (et non `static mut`) : évite le lint
// static_mut_refs (erreur en édition 2024). Sûr ici car wasm est mono-thread
// et l'hôte sérialise les appels par un mutex.
struct JournalCell(UnsafeCell<Vec<u8>>);
unsafe impl Sync for JournalCell {}
static LAST_JOURNAL: JournalCell = JournalCell(UnsafeCell::new(Vec::new()));

/// # Safety
/// Les pointeurs doivent référencer des tampons valides de la taille annoncée.
#[no_mangle]
pub unsafe extern "C" fn verify(
    receipt_ptr: *const u8,
    receipt_len: usize,
    image_id_ptr: *const u8,
    image_id_len: usize,
) -> i32 {
    if image_id_len != 32 {
        return 3;
    }
    let receipt_bytes = core::slice::from_raw_parts(receipt_ptr, receipt_len);
    let image_id_bytes = core::slice::from_raw_parts(image_id_ptr, image_id_len);

    let mut id = [0u8; 32];
    id.copy_from_slice(image_id_bytes);
    let digest = Digest::from_bytes(id);

    let receipt = match Receipt::try_from_slice(receipt_bytes) {
        Ok(r) => r,
        Err(_) => return 2,
    };

    match receipt.verify(digest) {
        Ok(()) => {
            *LAST_JOURNAL.0.get() = receipt.journal.bytes.clone();
            0
        }
        Err(_) => 1,
    }
}

/// # Safety
/// À appeler seulement après un `verify` retournant 0, avant tout `verify` suivant.
#[no_mangle]
pub unsafe extern "C" fn journal_ptr() -> *const u8 {
    (*LAST_JOURNAL.0.get()).as_ptr()
}

/// # Safety
/// Idem `journal_ptr`.
#[no_mangle]
pub unsafe extern "C" fn journal_len() -> usize {
    (*LAST_JOURNAL.0.get()).len()
}
