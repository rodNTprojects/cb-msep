// Host RISC Zero (brique A).
//
// 1) construit l'environnement avec D, min, max ;
// 2) produit la preuve (STARK) ;
// 3) la vérifie en NATIF (référence : doit égaler le verdict WASM) ;
// 4) sérialise le receipt en borsh + l'image id en 32 octets ;
// 5) écrit receipt.bin / imageid.bin dans le répertoire de sortie.
//
// PARAMÉTRABLE (P3, workload Phase 7). Sans variable d'environnement, le
// comportement est IDENTIQUE à l'origine : D = jeu d'exemple, [150000, 300000],
// donc C = a353c9...8414fc53. Le workload varie D et les bornes par item :
//
//   CBMSEP_D="price=90000;parcel=XY-9;partyA=Ann;partyB=Bo" \
//   CBMSEP_MIN=50000 CBMSEP_MAX=100000 \
//   ./host workload/receipts/deed42
//
// Le guest est inchangé : il lit (D, min, max) et engage C||min||max. L'image id
// ne dépend que de l'ELF, donc le expected_imageid épinglé reste valide.
//
// Sorties stdout parsables par le harnais (une valeur par ligne) :
//   C=<hex 32o>            engagement sha256(D)
//   PUBLICIN=<hex 16o>     min(8, LE) || max(8, LE)  -> arg --publicin du client
//   RECEIPT=<chemin>       receipt.bin écrit
//   BYTES=<n>              taille du receipt

use methods::{PREDICATE_ELF, PREDICATE_ID};
use risc0_zkvm::{default_prover, sha::Digest, ExecutorEnv};
use std::{fs, path::PathBuf};

const DEFAULT_D: &str = "price=250000;parcel=AB-12;partyA=Alice;partyB=Bob";
const DEFAULT_MIN: u64 = 150_000;
const DEFAULT_MAX: u64 = 300_000;

fn main() {
    // Entrées : variables d'environnement, repli sur le jeu d'exemple.
    let d_str = std::env::var("CBMSEP_D").unwrap_or_else(|_| DEFAULT_D.to_string());
    let is_default_d = d_str == DEFAULT_D;
    let d: Vec<u8> = d_str.into_bytes();
    let min: u64 = std::env::var("CBMSEP_MIN")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(DEFAULT_MIN);
    let max: u64 = std::env::var("CBMSEP_MAX")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(DEFAULT_MAX);
    assert!(min <= max, "bornes invalides: min > max");

    let env = ExecutorEnv::builder()
        .write(&d)
        .unwrap()
        .write(&min)
        .unwrap()
        .write(&max)
        .unwrap()
        .build()
        .unwrap();

    println!("Preuve en cours (STARK RISC Zero)... [min={min}, max={max}]");
    let prove_info = default_prover().prove(env, PREDICATE_ELF).unwrap();
    let receipt = prove_info.receipt;

    // Vérif native de référence : doit réussir.
    receipt.verify(PREDICATE_ID).expect("verif native echouee");
    println!("Verif native : VALIDE");

    // Sérialisation borsh (même format que la brique B) + image id 32 octets.
    let receipt_bytes = borsh::to_vec(&receipt).unwrap();
    let image_id = Digest::from(PREDICATE_ID);

    // Sortie : argv[1] si fourni, sinon testdata/ de CC_V (comportement d'origine).
    let out_dir = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("../../chaincode/verification/testdata"));
    fs::create_dir_all(&out_dir).unwrap();
    let receipt_path = out_dir.join("receipt.bin");
    fs::write(&receipt_path, &receipt_bytes).unwrap();
    fs::write(out_dir.join("imageid.bin"), image_id.as_bytes()).unwrap();

    // publicInHex = min(8, LE) || max(8, LE) — l'arg --publicin du client Attest.
    let mut pubin = Vec::with_capacity(16);
    pubin.extend_from_slice(&min.to_le_bytes());
    pubin.extend_from_slice(&max.to_le_bytes());

    let c_hex = hex::encode(&receipt.journal.bytes[..32]);
    // Lignes parsables (préfixes stables) :
    println!("C={c_hex}");
    println!("PUBLICIN={}", hex::encode(&pubin));
    println!("RECEIPT={}", fs::canonicalize(&receipt_path).unwrap().display());
    println!("BYTES={}", receipt_bytes.len());
    if is_default_d {
        println!(
            "attendu Phase 2 = a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53"
        );
    }
}
