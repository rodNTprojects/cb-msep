# Intégration de la brique B dans cbmsep-net

Ces fichiers ne forment **pas** un module à part : ils vont à leur place
définitive dans l'arbre `cbmsep-net`. Aucun dossier « phase ». Le contenu de
cette archive **reproduit déjà l'arbre cible** — extrais-la à la racine de
`cbmsep-net` et les fichiers se posent aux bons endroits.

## Placement

```
cbmsep-net/
├── chaincode/verification/
│   ├── verifier_stark.go        # NOUVEAU — hôte wazero, package verification
│   ├── verifier_stark_test.go   # NOUVEAU
│   ├── verifier.wasm            # généré par scripts/build_verifier.sh (//go:embed)
│   └── verification_contract.go # EXISTANT — y câbler VerifyProof (voir plus bas)
├── zk/
│   └── verifier-wasm/           # NOUVEAU — source Rust de la brique B
│       ├── Cargo.toml
│       └── src/lib.rs
└── scripts/
    └── build_verifier.sh        # NOUVEAU — build wasm -> chaincode/verification/
```

Le répertoire `zk/` accueillera aussi `zk/prover/` (brique A, à reconstruire).

## Ordre des opérations

1. Ajouter wazero au module du chaincode de vérification :
   ```bash
   cd chaincode/verification
   go get github.com/tetratelabs/wazero
   # si vendored :
   go mod vendor
   ```
2. Construire le module WASM et le déposer dans le package :
   ```bash
   bash scripts/build_verifier.sh
   ```
3. Câbler dans `verification_contract.go` : remplacer, dans
   `newVerificationContract()`, le stub `notWired{}` par une instance qui délègue
   `VerifyProof` au `WasmVerifier`. `VerifyBinding` (σ) reste la brique C.

## Points d'attention

- `//go:embed verifier.wasm` est résolu à la **compilation**. Le `.wasm` doit
  donc exister avant de packager/installer CC_V. Tant qu'il n'est pas construit,
  ne pas inclure `verifier_stark.go` dans le package — CC_V garde `notWired{}` et
  reste déployable.
- Les tests restent en `SKIP` jusqu'à ce que la brique A produise
  `chaincode/verification/testdata/receipt.bin` et `testdata/imageid.bin`.
- Même version `risc0-zkvm` (=3.0.6) et même version `borsh` côté brique A et
  côté `zk/verifier-wasm`, sinon les formats divergent.
