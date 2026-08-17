# Incrément 2a — activateurs de la Phase 7 : workload (P3) et inférence (A3)

## Ce que c'est

Deux verrous de la Phase 7 sautent d'un coup, parce qu'ils partagent la même
cause : le host de la brique A codait `D` en dur. Une fois `D` et les bornes
paramétrables, on obtient à la fois un workload réaliste (P3) et le calcul
d'inférence par prédicat (A3), qui réutilise la même liste de prédicats.

Le guest n'est pas touché. Il lit déjà `(D, min, max)` de façon générique et
engage `C || min || max`. L'image id ne dépend que de l'ELF du guest, pas des
entrées, donc le `expected_imageid` épinglé reste valide pour tout `D`.

## Contenu du tar

| Fichier | État | Rôle |
|---|---|---|
| `zk/prover/host/src/main.rs` | remplace | host paramétrable par variables d'env |
| `scripts/gen_workload.sh` | nouveau | génère N actes -> N preuves + manifeste |
| `scripts/analyze_inference.sh` | nouveau | A3 : fuite d'inférence par prédicat |
| `README_increment2a.md` | ce fichier | notes de livraison |

## P3 — host paramétrable

Sans variable d'environnement, le comportement est **identique** à l'origine :
`D` = jeu d'exemple, bornes `[150000, 300000]`, donc `C = a353c9…8414fc53`. Le
workload varie `D` et les bornes par item :

```bash
CBMSEP_D="price=90000;parcel=XY-09;partyA=Ann;partyB=Bo" \
CBMSEP_MIN=50000 CBMSEP_MAX=100000 \
./target/release/host workload/receipts/deed2
```

Le host imprime des lignes parsables : `C=…`, `PUBLICIN=…` (les bornes en
`min‖max` little-endian, l'argument `--publicin` du client Attest), `RECEIPT=…`,
`BYTES=…`. `gen_workload.sh` les capte pour construire le manifeste.

## A3 — fuite d'inférence

Une attestation vraie situe la valeur cachée dans `[min, max]`, indépendamment du
zero-knowledge. `analyze_inference.sh` chiffre cette fuite par prédicat. Pour un
intervalle de taille `k = max − min + 1`, sous prior uniforme, l'entropie
résiduelle vaut `log2(k)` bits. Avec un domaine a priori `N` (option `--domain`),
la fuite vaut `log2(N) − log2(k)` bits. C'est un calcul analytique, pas un
benchmark de latence.

Exemple de sortie :

```
  acte     predicat [min,max]         |revele| k entropie res.(b)
  deed1    [150000,300000]                150001           17.195
  deed2    [50000,100000]                  50001           15.610
```

Lecture : plus `k` est grand, moins l'attestation en dit. La fuite se règle au
niveau du prédicat, jamais dans le circuit.

## Coût honnête du workload

Chaque preuve STARK prend de plusieurs secondes à quelques minutes. Le nombre
d'items est donc volontairement modeste et affiché à l'exécution. Ce n'est pas
une charge de production : c'est un échantillon reproductible et varié. Aucune
troncature silencieuse — le compte d'items est imprimé.

## Installation

```bash
cd ~/cbmsep-net
tar -xzf increment2a_phase7.tar.gz     # remplace host/src/main.rs, ajoute 2 scripts
```

## Exécution

Prérequis : réseau up et déployé, toolchain RISC Zero présente (comme pour la
brique A d'origine).

```bash
bash scripts/gen_workload.sh                 # 5 actes par défaut -> workload/manifest.tsv
bash scripts/analyze_inference.sh            # A3 sur ces prédicats
bash scripts/analyze_inference.sh --domain 1000000   # + fuite si domaine connu
```

Spec personnalisée (TSV : `key <TAB> D <TAB> min <TAB> max`) :

```bash
bash scripts/gen_workload.sh mes_actes.tsv
```

## Vérifié avant livraison

Les deux scripts passent `bash -n`. L'analyseur d'inférence a tourné sur un
manifeste factice : entropies et fuites conformes (`log2(150001)=17.195`,
`log2(10^6)−17.195=2.737`). L'encodage `publicin` little-endian du host a été
recalculé et reproduit exactement `f049020000000000e093040000000000` pour
`[150000, 300000]`. Le changement du host est minime et n'ajoute aucune
dépendance (`hex` est déjà présent) ; il reste à recompiler chez toi, la
compilation Rust n'étant pas possible de mon côté.
