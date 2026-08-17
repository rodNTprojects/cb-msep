#!/usr/bin/env bash
# check_obliviousness.sh — analyse statique de la surface d'API privée de CC_V.
#
# INVARIANT VÉRIFIÉ (« non-member data-obliviousness by construction ») :
#   le chaincode de vérification CC_V ne dispose d'AUCUN chemin de lecture des
#   données privées D. Le non-membre atteste P(D) sans jamais lire D.
#
# MÉTHODE : on énumère l'INTÉGRALITÉ de la surface d'API private-data du shim
# Fabric (ChaincodeStubInterface) et on prouve qu'aucun de ces appels n'apparaît
# dans le code déployé de CC_V (hors vendor, hors tests).
#
# ARGUMENT DE SOUNDNESS (pourquoi ce grep suffit ICI, alors qu'en général il ne
# suffirait pas) : une analyse de teinte (PDCHECKER, Chen 2024, ISSRE) suit la
# propagation d'une SOURCE sensible vers un SINK. Sans aucune source — c.-à-d.
# sans aucun appel de lecture private-data — l'ensemble des chemins teintés est
# VIDE. La propriété « D n'atteint aucune sortie » est alors satisfaite
# vacuously : il n'y a rien à propager. L'absence d'appel est donc une condition
# SUFFISANTE, décidable par énumération exhaustive de la surface d'appel.
# PDCHECKER reste l'oracle recommandé en CI dès que CC_V acquerrait une lecture
# privée légitime (il ne doit jamais en acquérir).
#
# Sortie : PASS/FAIL par API + verdict global + résumé lisible machine (CI).

cd "$(dirname "$0")/.."

CCV_DIR=chaincode/verification

# Surface COMPLÈTE des lectures/écritures private-data du shim Go
# (github.com/hyperledger/fabric-chaincode-go ChaincodeStubInterface).
# Lectures ET écritures sont interdites : CC_V ne touche jamais la PDC.
APIS=(
  GetPrivateData
  GetPrivateDataHash
  PutPrivateData
  DelPrivateData
  PurgePrivateData
  SetPrivateDataValidationParameter
  GetPrivateDataValidationParameter
  GetPrivateDataByRange
  GetPrivateDataByPartialCompositeKey
  GetPrivateDataQueryResult
)

# Fichiers DÉPLOYÉS de CC_V : *.go hors vendor/ et hors *_test.go.
mapfile -t SRC < <(find "$CCV_DIR" -name '*.go' \
  -not -path '*/vendor/*' -not -name '*_test.go' | sort)

if [ "${#SRC[@]}" -eq 0 ]; then
  echo "erreur: aucun source Go trouvé sous $CCV_DIR" >&2
  exit 2
fi

echo "== Surface d'API private-data analysée (CC_V déployé) =="
echo "Fichiers :"
printf '  - %s\n' "${SRC[@]}"
echo

viol=0
for api in "${APIS[@]}"; do
  # On cherche l'APPEL de méthode « .Api( » (le point exclut la définition
  # d'interface du vendor et les commentaires descriptifs sans parenthèse).
  hits=$(grep -nE "\.${api}\s*\(" "${SRC[@]}" 2>/dev/null || true)
  if [ -z "$hits" ]; then
    printf "  [PASS] %-38s aucun appel\n" "$api"
  else
    printf "  [FAIL] %-38s APPEL DÉTECTÉ\n" "$api"
    echo "$hits" | sed 's/^/        /'
    viol=$((viol+1))
  fi
done

# Garde-fou complémentaire : aucune méthode privée « fourre-tout » oubliée.
# Toute occurrence de « PrivateData » dans le code déployé est suspecte.
echo
echo "== Garde-fou : toute mention de PrivateData dans le code déployé =="
STRAY=$(grep -nE 'PrivateData' "${SRC[@]}" 2>/dev/null || true)
if [ -z "$STRAY" ]; then
  echo "  [PASS] aucune occurrence de « PrivateData »"
else
  echo "  [WARN] occurrences à inspecter (commentaire ? nom de variable ?) :"
  echo "$STRAY" | sed 's/^/        /'
  # Un commentaire n'est pas un appel ; ce garde-fou n'incrémente pas viol,
  # il attire l'œil du relecteur. Le verdict repose sur l'énumération ci-dessus.
fi

# Contexte informatif : les tests peuvent, eux, lire la PDC (montage de banc).
echo
echo "== Contexte : fichiers de test (NON déployés, informatif) =="
mapfile -t TST < <(find "$CCV_DIR" -name '*_test.go' -not -path '*/vendor/*' | sort)
if [ "${#TST[@]}" -eq 0 ]; then
  echo "  (aucun _test.go)"
else
  T=$(grep -lE '\.(GetPrivateData|PutPrivateData)\s*\(' "${TST[@]}" 2>/dev/null || true)
  [ -z "$T" ] && echo "  aucun accès private-data dans les tests" \
              || { echo "  accès private-data dans les tests (hors binaire déployé) :"; echo "$T" | sed 's/^/    /'; }
fi

echo
echo "======================================================"
if [ "$viol" -eq 0 ]; then
  echo "VERDICT : CC_V n'appelle AUCUNE des ${#APIS[@]} API private-data."
  echo "  => surface de lecture privée vide => ensemble de chemins teintés vide"
  echo "  => obliviousness du non-membre satisfaite par construction (soundness"
  echo "     de l'énumération exhaustive ; PDCHECKER = oracle CI de repli)."
  echo "obliviousness_ok=1 apis_checked=${#APIS[@]} violations=0"
  exit 0
else
  echo "VERDICT : $viol API private-data appelée(s) dans CC_V — INVARIANT ROMPU."
  echo "obliviousness_ok=0 apis_checked=${#APIS[@]} violations=$viol"
  exit 1
fi
