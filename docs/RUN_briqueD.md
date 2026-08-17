# Brique D — end-to-end : Attest (TX2) via Fabric Gateway

Soumet la preuve + σ à `CC_V`, endossé par les non-membres sous `OutOf(2,3)`,
et lit l'attestation. C'est la démonstration on-chain complète.

## Fichiers

```
client/attest/          # client Fabric Gateway
├── go.mod
└── main.go             # lit receipt/sigma depuis des FICHIERS (pas d'argv géant)
```

## Ordre complet (réseau frais)

Un `down/up` régénère le crypto : il faut re-refresh (racines) et re-signer σ
(clés membres neuves). Le commitment C et le receipt, eux, ne changent pas
(déterministes, liés au guest, pas au réseau).

```bash
cd ~/cbmsep-net

# 1. réseau propre + chaincodes
bash scripts/down.sh
bash scripts/up.sh && bash scripts/channel.sh

# 2. matériel épinglé (racines membres neuves + image id) AVANT deploy
bash scripts/refresh_binding_material.sh
bash scripts/deploy.sh          # datacc (Org1/2) + verifycc (Org3/4/5) avec le vrai vérifieur

# 3. TX1 : un membre écrit D -> C=pending sur le ledger
bash scripts/submit.sh          # C = a353c9...  (status pending)

# 4. σ : les DEUX membres signent (key, C) -> fichier sigma.hex
cd client/sign_binding
go run . asset1 a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53 \
  Org1MSP=../../organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp \
  Org2MSP=../../organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp \
  > /tmp/sigma.hex
cd ../..

# 5. TX2 : Attest via le gateway (soumetteur = non-membre Org3)
cd client/attest
go mod tidy
go run . \
  --commitment a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53 \
  --sigma /tmp/sigma.hex
cd ../..
```

Attendu : `Attest OK` puis `ReadAttestation: {"key":"asset1","commitment":"a353c9...","status":"attested"}`.
La clé passe de *pending* (dans `CC_D`) à *attested* (dans `CC_V`), sans que le
non-membre ait jamais lu D.

## Cas négatifs (début de la Phase 6)

- **Mauvaise preuve** : `--receipt` sur un receipt corrompu -> `proof rejected`.
- **Mauvais C** : `--commitment` faux -> soit le binding échoue (σ ne couvre pas
  ce C), soit la soudure journal↔C -> `proof rejected`.
- **σ incomplet** : sigma avec un seul membre -> `binding rejected` (seuil 2).
- **Rejeu** : relancer Attest sur la même clé -> `already attested` (idempotence).

## Si l'endossement échoue à rassembler 2 non-membres

`SubmitTransaction` s'appuie sur la découverte de service pour trouver les
endosseurs Org4/Org5. Si le réseau n'a pas d'anchor peers configurés, la
collecte peut échouer. Deux remèdes : configurer les anchor peers du canal, ou
cibler explicitement les orgs endossantes via l'API `NewProposal(...,
WithEndorsingOrganizations("Org3MSP","Org4MSP"))` — dis-le-moi et je te fournis
cette variante (API à vérifier au préalable).

## Notes

- Le soumetteur est un **non-membre** (Org3) : c'est cohérent, TX2 est l'acte du
  non-membre. Le peer gateway (Org3, 9051) rassemble l'endossement `OutOf(2,3)`.
- Le TLS override `--peerHost peer0.org3.example.com` doit matcher un SAN du cert
  du peer (tu as ajouté localhost/127.0.0.1 ; le nom d'hôte est aussi présent).
- Adapte les chemins/orgs si ta topologie diffère (flags `--endpoint`, `--mspid`,
  `--mspdir`, `--tlscert`).
