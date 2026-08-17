// Guest RISC Zero — le cœur de l'attestation ZK.
//
// Lit D (privé), engage C = sha256(D), extrait le prix de D, et PROUVE que
// le prix est dans [min, max]. L'assertion échoue -> pas de preuve produite ;
// donc un receipt valide atteste « il existe D tel que sha256(D)=C et
// min <= price(D) <= max », sans révéler D.
//
// Journal (sorties publiques) = C(32) || min(8, LE) || max(8, LE).

#![no_main]

use risc0_zkvm::guest::env;
use sha2::{Digest, Sha256};

risc0_zkvm::guest::entry!(main);

fn parse_price(d: &[u8]) -> Option<u64> {
    let key = b"price=";
    let start = d.windows(key.len()).position(|w| w == key)? + key.len();
    let mut val: u64 = 0;
    let mut seen = false;
    for &b in &d[start..] {
        if b.is_ascii_digit() {
            val = val.checked_mul(10)?.checked_add((b - b'0') as u64)?;
            seen = true;
        } else {
            break;
        }
    }
    if seen {
        Some(val)
    } else {
        None
    }
}

fn main() {
    // Entrées (mêmes types/ordre que les .write du host).
    let d: Vec<u8> = env::read();
    let min: u64 = env::read();
    let max: u64 = env::read();

    // Engagement C = sha256(D).
    let c = Sha256::digest(&d);

    // Prédicat : min <= price(D) <= max.
    let price = parse_price(&d).expect("D ne contient pas 'price=<n>'");
    assert!(price >= min && price <= max, "predicat faux: price hors bornes");

    // Journal public : C || min || max.
    let mut out = Vec::with_capacity(48);
    out.extend_from_slice(&c);
    out.extend_from_slice(&min.to_le_bytes());
    out.extend_from_slice(&max.to_le_bytes());
    env::commit_slice(&out);
}
