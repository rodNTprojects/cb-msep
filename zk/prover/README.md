# zk/prover — brique A (prouveur RISC Zero)

Produit la preuve que la brique B vérifie. Le guest est le cœur de
l'attestation ; le host produit le receipt et le dépose là où le test
d'équivalence l'attend.

## Structure

```
zk/prover/
├── Cargo.toml              # workspace : host + methods
├── host/                   # produit receipt.bin + imageid.bin
│   ├── Cargo.toml
│   └── src/main.rs
└── methods/                # compile le guest, génère PREDICATE_ELF/ID
    ├── Cargo.toml
    ├── build.rs
    ├── src/lib.rs
    └── guest/              # le programme prouvé
        ├── Cargo.toml
        └── src/main.rs
```

## Ce que prouve le guest

« Il existe D tel que `sha256(D) = C` et `min <= price(D) <= max` », sans
révéler D. Journal public = `C(32) || min(8, LE) || max(8, LE)`. Avec le D de
la Phase 2, `C = a353c969...8414fc53`.

## Prérequis

Le toolchain RISC Zero (rzup) doit être installé — c'est le toolchain `risc0`
déjà présent chez toi (visible dans `rustup show`). risc0-build l'utilise pour
compiler le guest.

## Lancer

```bash
cd ~/cbmsep-net/zk/prover
cargo run --release --bin host
```

Le host affiche la vérif native (VALIDE), la valeur de C, et écrit dans
`../../chaincode/verification/testdata/` :
- `receipt.bin`  — receipt sérialisé borsh
- `imageid.bin`  — 32 octets (Digest::as_bytes)

Le chemin par défaut suppose un lancement depuis `zk/prover`. Sinon, passe le
dossier en argument : `cargo run --release --bin host -- /chemin/vers/testdata`.

## Ensuite : le test d'équivalence

```bash
cd ~/cbmsep-net/chaincode/verification
go test -run 'Equivalence|Tampered' -v
```

Attendu : `TestVerifyEquivalence` PASSE (verdict WASM = VALIDE, journal
commençant par C) et `TestRejectsTamperedReceipt` PASSE (receipt corrompu
rejeté). Cela ferme la boucle : le verdict WASM égale le verdict natif du host.

## Cohérence de version (impératif)

`risc0-zkvm` **=3.0.6** partout — guest, host, et `zk/verifier-wasm` — plus
`risc0-build` =3.0.6 et `borsh` 1.x des deux côtés. Un écart casse le format du
receipt ou l'image id.

## Note performance (optionnel)

Le sha256 tourne ici dans le circuit (correct mais non accéléré). Pour accélérer,
RISC Zero fournit un patch `sha2` ; à ajouter plus tard si le temps de preuve
gêne. Pour valider l'équivalence, la version simple suffit.
