# CB-MSEP — Tests et méthodologie d'évaluation

Ce document décrit comment CB-MSEP est testé et évalué, et pourquoi chaque test
mesure ce qu'il prétend mesurer. Il accompagne le guide d'implémentation : le
guide dit comment reconstruire le système, ce document dit comment on le met à
l'épreuve. Il couvre les Phases 5 (fonctionnel), 6 (sécurité) et 7 (évaluation
quantitative).

## 1. Principe directeur

Les suites de test attaquent le système **déjà déployé**. On ne redéploie rien
entre les scénarios : on change les entrées, jamais le code. C'est exactement la
posture d'un adversaire réel, qui ne recompile pas le chaincode mais lui soumet
des transactions malformées. Cette contrainte explique aussi leur rapidité — un
rejet échoue tôt, à l'endossement, avant tout commit.

Un test livre une **évidence**, pas une preuve. La distinction structure toute la
Phase 6. Trois familles de garanties coexistent, et le test joue un rôle
différent dans chacune.

| Famille | Garantie de fond | Rôle du test |
|---|---|---|
| Cryptographique | Preuve des primitives (soundness du STARK, infalsifiabilité ECDSA) | Test négatif : falsifier, observer le rejet |
| Invariant no-private-read | Analyse statique de la surface d'API | Énumération exhaustive + observation du ledger |
| Seuil `t-1` | Politique d'endossement Fabric | Démontrer qu'en-dessous du seuil, rien ne commite |

Aucun test ne « prouve » la soundness du STARK. Le test SEC2 montre qu'une preuve
corrompue est rejetée : c'est le cas représentatif d'une propriété héritée de la
primitive, pas une reconstruction de sa preuve.

## 2. Phase 5 — tests fonctionnels

Fichier : `scripts/test_phase5.sh`. Prérequis : réseau up et déployé, brique A
exécutée. Chaque scénario affiche attendu, obtenu, et un verdict. Cible : 8 PASS.

**S1 — chemin heureux.** Un membre écrit `D` (TX1, *pending*). Les deux membres
signent σ. Le non-membre atteste (TX2). Résultat attendu : `Attest OK` et statut
*attested*.

**S2 — précondition.** On atteste une clé avec un σ signé pour une autre clé. Le
binding ne couvre pas la clé revendiquée : `binding rejected`. Le système refuse
proprement, sans effet de bord.

**S3 — rejeu idempotent.** Ré-attester une clé déjà attestée renvoie
`already attested`. Aucune double écriture ; l'opération est sûre à rejouer.

**S4 — Cancel et garde.** Un membre annule un dossier *pending* : il passe
*cancelled*. Ré-annuler renvoie `not pending`. La garde n'autorise que la
transition *pending → cancelled*.

**S5 — concurrence MVCC.** Deux `Attest` simultanés visent la même clé. Ils
lisent tous deux l'état *pending* (version v0), endossent, puis soumettent.
Fabric valide en série. La première transaction commite et fait passer la version
à v1 ; la seconde échoue, soit en `MVCC_READ_CONFLICT` (sa lecture v0 est
périmée), soit sur la garde applicative `already attested` si l'ordonnancement
les a sérialisées. Les deux issues sont des rejets légitimes. Le test l'affirme
en trois assertions : exactement un `Attest OK`, un perdant motivé, un unique
enregistrement attesté au grand livre. Il ne dépend pas du timing exact, donc ne
« flappe » pas.

Ce dernier scénario garantit l'absence de double attestation sous course. C'est
la propriété qui rend l'attestation atomique du point de vue applicatif.

## 3. Phase 6 — tests de sécurité

Fichier : `scripts/test_phase6.sh`. Chaque scénario porte l'étiquette de la
propriété testée et sa source dans la littérature. Cible : 6 PASS, plus SEC6 en
analyse.

**SEC1 — injection de commitment** (Wang 2021). On atteste en revendiquant un
`C` que les membres n'ont pas signé. Le binding est rompu : `binding rejected`.
Un non-membre ne peut pas fabriquer une attestation pour un engagement arbitraire.

**SEC2 — infalsifiabilité de la preuve** (soundness du STARK). On corrompt le
receipt par retournements d'octets, puis on l'atteste. Résultat : `proof rejected`.
Le vérifieur WASM rejette toute preuve altérée.

**SEC3 — liaison à l'énoncé**. Preuve et σ valides, mais bornes `min/max`
falsifiées. La soudure `journal ↔ publicIn` détecte l'écart : `proof rejected`.
On ne peut pas rejouer une preuve honnête sous un énoncé différent.

**SEC4 — seuil** (cœur de la contribution). On rend Org4 et Org5 injoignables.
Un seul non-membre ne satisfait pas `OutOf(2,3)`. Aucune attestation ne commite.
La garantie de seuil vient de la politique d'endossement, pas du code applicatif ;
le test le démontre à la frontière.

**SEC5 — data-obliviousness** (Chen 2024). Deux volets. Empirique : le non-membre
Org3 n'a aucune base privée `$$p` en clair, le membre Org1 oui. Statique :
`check_obliviousness.sh` prouve que `CC_V` n'appelle aucune API de lecture privée
(section 4). SEC5(b) lit le verdict machine de ce script.

**SEC6 — inférence** (Islam, Dharani). Analyse, pas pass/fail. Une attestation
vraie révèle de l'information au niveau du prédicat, indépendamment du
zero-knowledge. Pour `150000 ≤ price ≤ 300000`, une attestation vraie situe
`price` dans 150 001 valeurs. La réduction d'entropie est bornée par la
granularité du prédicat. On la quantifie par prédicat, jamais dans le circuit.
Cette quantification est la tâche A3, mesurée en Phase 7 (section 5).

Ces scénarios sont les cas **représentatifs** de chaque revendication, pas un
fuzzing exhaustif. Le fuzzing systématique et l'intégration de PDCHECKER en CI
sont des extensions, pas des prérequis à la contribution.

## 4. Analyse statique d'obliviousness

Fichier : `scripts/check_obliviousness.sh`. Indépendant du réseau ; s'exécute sur
les sources. Il vérifie l'invariant central : `CC_V` ne dispose d'aucun chemin de
lecture des données privées `D`.

La méthode énumère l'intégralité de la surface d'API private-data du shim Fabric
et prouve qu'aucun de ces appels n'apparaît dans le code déployé de `CC_V` (hors
`vendor/`, hors `*_test.go`). Dix fonctions couvrent lectures et écritures :
`GetPrivateData`, `GetPrivateDataHash`, `PutPrivateData`, `DelPrivateData`,
`PurgePrivateData`, `SetPrivateDataValidationParameter`,
`GetPrivateDataValidationParameter`, `GetPrivateDataByRange`,
`GetPrivateDataByPartialCompositeKey`, `GetPrivateDataQueryResult`.

L'argument de soundness justifie pourquoi un grep suffit ici, alors qu'en général
il ne suffirait pas. Une analyse de teinte comme PDCHECKER (Chen 2024) suit la
propagation d'une source sensible vers un sink. Sans aucune source — sans aucun
appel de lecture privée — l'ensemble des chemins teintés est vide. La propriété
« `D` n'atteint aucune sortie » est alors satisfaite de façon vacuously vraie : il
n'y a rien à propager. L'absence d'appel, décidable par énumération exhaustive de
la surface, est donc une condition **suffisante**. PDCHECKER reste l'oracle
recommandé en CI si `CC_V` acquérait un jour une lecture privée légitime — ce
qu'il ne doit jamais faire.

Le script émet un verdict lisible machine (`obliviousness_ok=1`, code de sortie 0)
directement exploitable en intégration continue.

## 5. Phase 7 — évaluation quantitative

Fichier : `scripts/test_phase7.sh`. Harnais léger, sur un banc unique, N
répétitions, moyenne et écart-type. Objectif : chiffrer le prix de
l'obliviousness, sans le masquer.

### 5.1 Configurations comparées

Trois configurations sur le **même** banc, pour que les écarts soient imputables
au protocole et non au matériel.

| Configuration | Politique | Rôle |
|---|---|---|
| Native PDC | membres seuls, écriture privée nue | plancher |
| ZK-Only | `OutOf(1,3)`, vérif sans seuil | isole le coût de la vérification |
| Full CB-MSEP | `OutOf(2,3)`, vérif + binding + seuil | protocole complet |

### 5.2 Métriques

Deux niveaux, à la manière de FabZK. Micro : génération de preuve (hors chaîne),
latence TX1, latence TX2, tailles (receipt, empreinte on-ledger). Macro : surcoût
en pourcentage de Full CB-MSEP contre Native PDC. Ce surcoût est le prix de
l'obliviousness ; on le reporte tel qu'il tombe.

### 5.3 Passage à l'échelle

Balayage de 2 à 5 non-membres, et variation de la taille de `D`. On mesure comment
la latence d'attestation et l'empreinte évoluent avec le nombre d'endosseurs
requis et le volume de données engagées.

### 5.4 Workload et inférence

Le workload réaliste, façon FabZK, produit des `D` variés donnant des `C` variés,
une preuve par acte. Il exige de paramétrer le host de la brique A pour accepter
`D` et les bornes en arguments. Cette même paramétrisation débloque A3 : pour
chaque prédicat du workload, on calcule la taille de l'ensemble révélé et
l'entropie résiduelle. A3 est un calcul analytique, pas un benchmark de latence ;
il partage seulement la liste de prédicats de la Phase 7.

### 5.5 Lecture honnête

Native PDC est TX1 seul. CB-MSEP total est TX1, plus la génération de preuve, plus
l'attestation TX2. Le surcoût est la somme des deux derniers termes. La borne
native de la seule vérification, mesurée hors chaincode, avoisine 66 ms ; sa part
exacte dans TX2 demande une instrumentation du chaincode ou Caliper. Ces
raffinements sont documentés comme extensions, pas dissimulés.

## 6. Reproduire les suites

Depuis `~/cbmsep-net`, réseau up et déployé, brique A exécutée.

```bash
bash scripts/check_obliviousness.sh   # indépendant du réseau
bash scripts/test_phase5.sh           # attendu : 8 PASS, 0 FAIL
bash scripts/test_phase6.sh           # attendu : 6 PASS, 0 FAIL (+ SEC6 analyse)
bash scripts/test_phase7.sh           # mesures (N=15 par défaut)
```

## 7. Correspondance test ↔ revendication

| Test | Revendication du papier | Nature de la garantie |
|---|---|---|
| S1–S3 | Cycle d'attestation correct et idempotent | fonctionnelle |
| S4 | Sortie *pending* auditable | fonctionnelle |
| S5 | Pas de double attestation sous course | fonctionnelle (MVCC) |
| SEC1 | Pas d'attestation sur un `C` non signé | héritée (ECDSA) |
| SEC2 | Pas d'attestation sur preuve falsifiée | héritée (STARK) |
| SEC3 | Preuve liée à son énoncé | soudure `journal ↔ publicIn` |
| SEC4 | Seuil `t` de non-membres requis | politique d'endossement |
| SEC5 | Non-membre aveugle à `D` | statique exhaustive + ledger |
| SEC6 / A3 | Fuite d'inférence bornée par prédicat | analytique |
| Phase 7 | Coût de l'obliviousness quantifié | mesure |
