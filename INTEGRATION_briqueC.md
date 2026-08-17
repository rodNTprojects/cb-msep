# Intégration brique C (binding ECDSA/MSP) + câblage

L'archive reproduit l'arbre `cbmsep-net` ; extrais-la à la racine, elle fusionne.

## Fichiers

```
chaincode/verification/
├── binding.go                 # NOUVEAU — VerifyBinding (ECDSA/MSP, racines épinglées)
├── verifier_wire.go           # NOUVEAU — compose brique B+C, soude journal<->commitment
├── verification_contract.go   # MODIFIÉ — newVerificationContract() câble le vrai vérifieur
├── wiring_test.go             # NOUVEAU — teste VerifyProof câblé (soudure C)
├── member_roots/              # (généré par le script) <MSPID>.pem
└── expected_imageid.bin       # (généré par le script) image id du guest
scripts/refresh_binding_material.sh   # NOUVEAU — dépose racines + image id
client/sign_binding/           # NOUVEAU — outil membre : génère sigmaHex
```

## Ordre de build (impératif — 3 artefacts épinglés via //go:embed)

Le package `CC_V` ne compile qu'une fois présents : `verifier.wasm`, `member_roots/*.pem`,
`expected_imageid.bin`. Donc, depuis la racine `cbmsep-net`, dans l'ordre :

```bash
# 1) le wasm (brique B) — si pas déjà fait
bash scripts/build_verifier.sh

# 2) la preuve (brique A) — produit testdata/receipt.bin + imageid.bin
cd zk/prover && cargo run --release --bin host && cd ../..

# 3) le matériel épinglé (racines membres + image id)
bash scripts/refresh_binding_material.sh

# 4) dépendances Go + build
cd chaincode/verification
go get github.com/tetratelabs/wazero   # si pas déjà
go mod vendor
go build ./...
```

## Test local (avant tout déploiement)

```bash
cd chaincode/verification
go test -run 'Smoke|Equivalence|Wired' -v
```

`TestWiredVerifyProofBindsCommitment` doit passer : preuve correcte acceptée, commitment falsifié
refusé, bornes falsifiées refusées. C'est la validation de la soudure journal↔commitment.

## Générer sigmaHex (côté membres) et appeler Attest

```bash
# blob signé par les DEUX membres (seuil requiredMembers = 2)
cd client/sign_binding
SIGMA=$(go run . asset1 a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53 \
  Org1MSP=../../organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp \
  Org2MSP=../../organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp)

# proofHex = hex(receipt.bin) ; publicInHex = min||max (u64 LE)
PROOF=$(xxd -p -c 0 ../../chaincode/verification/testdata/receipt.bin)
PUBIN=f049020000000000e093040000000000
```

Puis `Attest(key, commitmentHex, sigmaHex, proofHex, publicInHex)` — via le **SDK** (le proofHex de
~442 K caractères dépasse la limite CLI `MAX_ARG_STRLEN`). L'ordre des args suit la signature
existante d'`Attest`.

## Rappels de conception (cf. doc projet CB-MSEP_brique_C_binding)

- Message signé : `CBMSEP-BIND-v1|<key>|<commitmentHex>`, SHA-256 puis ECDSA.
- Autorisation déterministe : `cert.CheckSignatureFrom(racine)` (pas de `time.Now`).
- Les racines changent à chaque regénération cryptogen → toujours relancer le script de refresh
  après un `down/up` avant de repackager `CC_V`.
- Fail-closed : si le matériel épinglé manque, `CC_V` panique au démarrage (jamais de stub accepté).
