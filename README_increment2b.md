# Incrément 2b — passage à l'échelle par nombre d'orgs (P4) et baseline ZK-Only (P2)

## Ce que c'est

Le réseau passe de 5 à 7 organisations : 2 membres (Org1, Org2) et 5 non-membres
(Org3 à Org7). On fait ensuite varier le nombre de non-membres endosseurs de 2 à 5
via la politique d'endossement de variantes `verifycc`, et on mesure la latence
d'attestation en fonction de ce nombre. La baseline ZK-Only (un seul endosseur,
seuil t=1) tombe comme cas particulier.

Choix de conception : le réseau est **statique** à 7 orgs, toutes présentes dès la
genèse. On ne fait pas rejoindre des orgs dynamiquement — cette voie exige des
mises à jour de configuration de canal, fragiles et hors sujet pour un banc. C'est
la politique de chaque définition `verifycc`, pas l'appartenance au canal, qui
fait varier n.

## Contenu du tar

| Fichier | État | Rôle |
|---|---|---|
| `crypto-config.yaml` | remplace | ajoute Org6, Org7 |
| `configtx.yaml` | remplace | ajoute Org6/Org7 + profil 7 orgs |
| `compose/compose-net.yaml` | remplace | ajoute peers + CouchDB Org6/Org7 |
| `scripts/env.sh` | remplace | boucle sur 1..7 |
| `scripts/channel.sh` | remplace | joint les 7 peers |
| `scripts/deploy_scaling.sh` | nouveau | variantes verifycc par sous-ensemble |
| `scripts/test_phase7_scaling.sh` | nouveau | balayage latence(n) |
| `README_increment2b.md` | ce fichier | runbook |

`scripts/up.sh` est inchangé : il monte tout le compose et n'a pas de boucle
par org.

## Topologie 7 orgs

| Org | Rôle | Peer | CouchDB | Operations |
|---|---|---|---|---|
| Org1 | membre | 7051 | 5984 | 9441 |
| Org2 | membre | 8051 | 6984 | 9442 |
| Org3 | non-membre | 9051 | 7984 | 9443 |
| Org4 | non-membre | 10051 | 8984 | 9444 |
| Org5 | non-membre | 11051 | 9984 | 9445 |
| Org6 | non-membre | 12051 | 10984 | 9446 |
| Org7 | non-membre | 13051 | 11984 | 9447 |

Ports par formule : peer `7051+(n-1)·1000`, CouchDB `5984+(n-1)·1000`,
operations `9440+n`. Les cinq premières orgs sont identiques à ton fichier actuel.

## Variantes déployées

| Nom | Politique | n | t | Rôle |
|---|---|---|---|---|
| `verifycc_zk1` | OutOf(1, Org3-5) | 3 | 1 | baseline ZK-Only (P2) |
| `verifycc_n2` | OutOf(2, Org3-4) | 2 | 2 | échelle n=2 |
| `verifycc_n3` | OutOf(2, Org3-5) | 3 | 2 | échelle n=3 |
| `verifycc_n4` | OutOf(3, Org3-6) | 4 | 3 | échelle n=4 |
| `verifycc_n5` | OutOf(3, Org3-7) | 5 | 3 | échelle n=5 |

Seuil t = majorité = ⌊n/2⌋+1. Chaque définition a son propre namespace d'état,
isolé des autres. La majorité de lifecycle (4 orgs sur 7) est atteinte en faisant
approuver la définition par les 7 orgs (les endosseurs avec package-id, les autres
sans).

## Séquence complète (réseau neuf)

La topologie change, donc il faut régénérer le matériel cryptographique et le bloc
de genèse — un simple redéploiement ne suffit pas.

```bash
cd ~/cbmsep-net
tar -xzf increment2b_scaling.tar.gz    # remplace configs + env/channel, ajoute 2 scripts

bash scripts/down.sh                    # repartir propre
bash scripts/up.sh                      # cryptogen 7 orgs + genesis + 15 conteneurs
sleep 12                                # 7 peers : laisser l'écoute TLS s'ouvrir
bash scripts/channel.sh                 # joint les 7 peers
bash scripts/deploy.sh                  # datacc (membres) + verifycc de base
bash scripts/deploy_scaling.sh          # verifycc_zk1 + verifycc_n2..n5
cd zk/prover && cargo build --release --bin host && cd ~/cbmsep-net
( cd zk/prover && ./target/release/host )   # brique A : receipt.bin de référence
bash scripts/test_phase7_scaling.sh     # latence(n), 15 reps par variante
```

## Charge machine — à savoir

Sept peers, sept CouchDB, un orderer : 15 conteneurs, plus un conteneur de
chaincode par peer endosseur et par variante `verifycc`. Sous WSL, prévoir la
mémoire (le `.wslconfig` du guide, section 1). Si un peer tarde à répondre au
déploiement, rallonger les temporisations.

## Point de vigilance : découverte des endosseurs

Le client se connecte à Org3 et laisse la gateway découvrir les autres endosseurs
selon la politique. Les anchor peers sont fixés à la genèse, donc la découverte
fonctionne. Si une attestation n=4 ou n=5 échoue en `failed to endorse` sans
message de contenu, c'est la découverte : forcer les orgs endosseuses côté client
(`WithEndorsingOrganizations`) ou vérifier que les peers Org6/Org7 sont bien
joints et gossipent.

## Ce que mesure le harnais

La latence d'attestation TX2 par variante, moyenne ± écart-type sur N reps. CC_V
étant indépendant de CC_D, `Attest` n'exige pas de submit préalable : on mesure
TX2 pur, clés fraîches par rep. La variable est n ; D et le prédicat restent
fixes (la variation de D, c'est P3 / `gen_workload.sh`).

La courbe latence(n) isole le coût du seuil de confiance : chaque non-membre
requis en plus ajoute une collecte de signature à l'endossement et une validation.
ZK-Only (t=1) est le plancher ; n=5, t=3 le sommet mesuré. L'empreinte on-ledger
(nombre de signatures d'endossement par bloc) croît avec t ; sa mesure exacte
demande l'inspection de bloc, notée comme raffinement.

## Vérifié avant livraison

Les trois YAML se chargent sans erreur ; le profil de canal liste bien 7 orgs ;
les blocs compose des orgs 1 à 5 sont byte-identiques à ton fichier actuel. Les
quatre scripts passent `bash -n`. Les fonctions de politique et de flags peer ont
été testées à part : `OutOf(3,'Org3MSP.member'..'Org7MSP.member')` et les ports
9051→13051 sortent corrects. Rien de tout cela n'a pu être exécuté contre Fabric
de mon côté ; la première passe sur ta machine reste la validation réelle.
