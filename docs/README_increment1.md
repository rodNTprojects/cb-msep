# Incrément 1 — montée en rigueur des Phases 5-6

## Ce que c'est

Deux faiblesses des suites de test existantes sont corrigées, sans toucher au
code du chaincode ni redéployer quoi que ce soit. L'incrément ne modifie que des
scripts de test et ajoute un vérificateur statique. Il se fusionne dans
`~/cbmsep-net` par-dessus l'existant.

Deux tâches sont traitées, A1 et A2.

- **A1** transforme le test de concurrence MVCC, jusqu'ici décrit à la main dans
  un commentaire, en un scénario scripté et déterministe.
- **A2** remplace un contrôle d'obliviousness qui ne cherchait qu'une seule
  fonction par une analyse exhaustive des dix API de données privées, assortie
  d'un argument de correction.

## Pourquoi c'était nécessaire

Avant cet incrément, deux points affaiblissaient la crédibilité des tests.

Le scénario MVCC de la Phase 5 n'était pas exécuté. Le script se terminait sur une
note invitant à le « démontrer manuellement ». Un relecteur ne pouvait pas le
rejouer. La propriété « pas de double attestation sous course » restait affirmée,
pas testée.

Le contrôle d'obliviousness de la Phase 6 cherchait la présence d'une seule
fonction, `GetPrivateData`. Or l'API de données privées de Fabric compte dix
fonctions. Un appel à `GetPrivateDataHash` ou `GetPrivateDataByRange` serait passé
inaperçu. Le test donnait une fausse assurance : il pouvait afficher PASS alors
qu'une lecture privée existait par une autre fonction.

## Contenu du tar

| Fichier | État | Rôle |
|---|---|---|
| `scripts/test_phase5.sh` | remplace l'existant | ajoute le scénario S5 scripté |
| `scripts/check_obliviousness.sh` | nouveau | analyse statique des 10 API privées |
| `scripts/test_phase6.sh` | remplace l'existant | SEC5(b) appelle le nouveau script |
| `docs/CB-MSEP_tests_methodology.md` | nouveau | documentation de méthodologie |
| `README_increment1.md` | ce fichier | notes de livraison |

## A1 — scénario MVCC scripté (S5)

Le test lance deux `Attest` en parallèle sur la même clé, avec `&` puis `wait`,
chacun redirigé vers son propre journal. Les deux transactions lisent l'état
*pending* en version v0, endossent, puis soumettent. Fabric valide en série : la
première commite et fait passer la clé en v1, la seconde échoue.

Le perdant échoue de l'une des deux façons possibles, toutes deux légitimes. En
concurrence réelle, sa lecture v0 est périmée à la validation : `MVCC_READ_CONFLICT`.
Si l'ordonnancement a séparé les deux transactions, la seconde voit déjà l'état
*attested* à l'endossement et se fait refuser par la garde applicative
`already attested`, avant même la validation MVCC.

Le test ne présume pas lequel des deux chemins se produit. Il vérifie trois
choses : exactement un `Attest OK`, un perdant dont le rejet est motivé, et un
unique enregistrement attesté au grand livre. Il ne dépend donc pas du timing et
ne produit pas de faux échecs intermittents. La Phase 5 passe de 6 à 8 assertions.

## A2 — analyse statique d'obliviousness

`check_obliviousness.sh` énumère l'intégralité de la surface d'API de données
privées du shim Fabric et prouve qu'aucun de ces appels n'apparaît dans le code
déployé de `CC_V`, c'est-à-dire hors `vendor/` et hors fichiers `*_test.go`.

Les dix fonctions couvrent lectures et écritures :

    GetPrivateData                        GetPrivateDataByRange
    GetPrivateDataHash                    GetPrivateDataByPartialCompositeKey
    PutPrivateData                        GetPrivateDataQueryResult
    DelPrivateData                        SetPrivateDataValidationParameter
    PurgePrivateData                      GetPrivateDataValidationParameter

Le script cherche l'appel de méthode, motif `.Fonction(`, ce qui exclut la
définition d'interface présente dans le `vendor/` et les commentaires. Un
garde-fou signale en plus toute occurrence résiduelle du terme `PrivateData`,
pour attirer l'œil du relecteur sur un éventuel nom de variable ou commentaire.

Argument de correction. Une analyse de teinte, comme PDCHECKER (Chen 2024), suit
la propagation d'une source sensible vers une sortie. Sans aucune source de
lecture privée, l'ensemble des chemins teintés est vide. La propriété « `D`
n'atteint aucune sortie » est alors satisfaite de façon vacuously vraie : il n'y a
rien à propager. L'absence d'appel, décidable par énumération exhaustive de la
surface, est donc une condition suffisante. PDCHECKER reste l'oracle recommandé en
intégration continue si `CC_V` acquérait un jour une lecture privée légitime, ce
qu'il ne doit jamais faire.

Le script émet un verdict lisible machine, `obliviousness_ok=1` avec code de
sortie 0, directement exploitable en CI. SEC5(b) de la Phase 6 lit ce verdict au
lieu de l'ancien grep à une fonction.

## Installation

Depuis la racine du projet, extraire par-dessus l'existant.

```bash
cd ~/cbmsep-net
tar -xzf increment1_phase56.tar.gz
```

Cela écrase `scripts/test_phase5.sh` et `scripts/test_phase6.sh`, ajoute
`scripts/check_obliviousness.sh` et `docs/CB-MSEP_tests_methodology.md`.

## Exécution

Prérequis : réseau up et déployé (Phase 4), brique A exécutée (les fichiers
`receipt.bin` et `imageid.bin` présents sous `testdata/`).

```bash
bash scripts/check_obliviousness.sh   # indépendant du réseau
bash scripts/test_phase5.sh           # attendu : 8 PASS, 0 FAIL
bash scripts/test_phase6.sh           # attendu : 6 PASS, 0 FAIL, plus SEC6 en analyse
```

`check_obliviousness.sh` n'a besoin ni du réseau ni du déploiement : il lit les
sources. Les deux suites, elles, attaquent le système déjà déployé.

## Vérification faite avant livraison

Les trois scripts passent `bash -n`. Le vérificateur d'obliviousness a été testé
sur une arborescence factice : il ignore correctement la définition d'interface du
`vendor/` et les fichiers de test, affiche PASS et code 0 sur du code propre, et
bascule en FAIL avec code 1 dès qu'un `GetPrivateData` est injecté dans une source
déployée.
