// Brique D — client Fabric Gateway : soumet Attest (TX2) à CC_V.
//
// Le proof (~442 K caractères hex) est lu depuis un FICHIER, jamais passé en
// argument de ligne de commande (sinon MAX_ARG_STRLEN comme la CLI peer).
//
// v2 : en cas d'échec, déballe les *details* gRPC du gateway pour afficher le
// vrai message de l'endosseur (ex. "binding rejected", "proof rejected") au lieu
// du générique "failed to endorse".
package main

import (
	"crypto/x509"
	"encoding/hex"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/hyperledger/fabric-gateway/pkg/client"
	"github.com/hyperledger/fabric-gateway/pkg/hash"
	"github.com/hyperledger/fabric-gateway/pkg/identity"
	"github.com/hyperledger/fabric-protos-go-apiv2/gateway"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/status"
)

func main() {
	endpoint := flag.String("endpoint", "localhost:9051", "adresse gateway (peer non-membre Org3)")
	peerHost := flag.String("peerHost", "peer0.org3.example.com", "nom TLS (SNI) du peer gateway")
	tlsCert := flag.String("tlscert",
		"organizations/peerOrganizations/org3.example.com/peers/peer0.org3.example.com/tls/ca.crt",
		"racine TLS du peer")
	mspID := flag.String("mspid", "Org3MSP", "MSP du soumetteur (un non-membre)")
	mspDir := flag.String("mspdir",
		"organizations/peerOrganizations/org3.example.com/users/User1@org3.example.com/msp",
		"répertoire MSP du soumetteur")
	channel := flag.String("channel", "cbmsep", "canal")
	chaincode := flag.String("chaincode", "verifycc", "chaincode CC_V")
	key := flag.String("key", "asset1", "clé de l'actif")
	commitment := flag.String("commitment", "", "commitmentHex (C) — requis")
	publicin := flag.String("publicin", "f049020000000000e093040000000000", "publicInHex (min||max, u64 LE)")
	receiptPath := flag.String("receipt", "chaincode/verification/testdata/receipt.bin", "chemin du receipt.bin")
	sigmaPath := flag.String("sigma", "", "fichier contenant sigmaHex (sortie de sign_binding) — requis")
	flag.Parse()

	if *commitment == "" || *sigmaPath == "" {
		fatal("--commitment et --sigma sont requis")
	}

	receipt, err := os.ReadFile(*receiptPath)
	must(err, "lecture receipt")
	proofHex := hex.EncodeToString(receipt)

	sigmaBytes, err := os.ReadFile(*sigmaPath)
	must(err, "lecture sigma")
	sigmaHex := strings.TrimSpace(string(sigmaBytes))

	tlsPEM, err := os.ReadFile(*tlsCert)
	must(err, "lecture TLS CA")
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(tlsPEM) {
		fatal("racine TLS invalide")
	}
	conn, err := grpc.NewClient(*endpoint,
		grpc.WithTransportCredentials(credentials.NewClientTLSFromCert(pool, *peerHost)))
	must(err, "connexion gRPC")
	defer conn.Close()

	id := loadIdentity(*mspID, *mspDir)
	sign := loadSign(*mspDir)

	gw, err := client.Connect(id,
		client.WithSign(sign),
		client.WithHash(hash.SHA256),
		client.WithClientConnection(conn),
		client.WithEndorseTimeout(60*time.Second),
		client.WithSubmitTimeout(60*time.Second),
		client.WithEvaluateTimeout(30*time.Second),
	)
	must(err, "connexion gateway")
	defer gw.Close()

	contract := gw.GetNetwork(*channel).GetContract(*chaincode)

	fmt.Printf("Attest(key=%s) |proofHex|=%d |sigmaHex|=%d\n", *key, len(proofHex), len(sigmaHex))
	res, err := contract.SubmitTransaction("Attest", *key, *commitment, sigmaHex, proofHex, *publicin)
	if err != nil {
		fatal("Attest a échoué: " + gatewayError(err))
	}
	fmt.Printf("Attest OK. Résultat: %s\n", string(res))

	att, err := contract.EvaluateTransaction("ReadAttestation", *key)
	if err != nil {
		fatal("ReadAttestation: " + gatewayError(err))
	}
	fmt.Printf("ReadAttestation: %s\n", string(att))
}

// gatewayError déballe les details gRPC du gateway pour exposer le message réel
// renvoyé par le chaincode chez l'endosseur.
func gatewayError(err error) string {
	st := status.Convert(err)
	msg := st.Message()
	for _, d := range st.Details() {
		if ed, ok := d.(*gateway.ErrorDetail); ok {
			msg += fmt.Sprintf(" | endorser=%s mspId=%s: %s", ed.GetAddress(), ed.GetMspId(), ed.GetMessage())
		}
	}
	return msg
}

func loadIdentity(mspID, mspDir string) *identity.X509Identity {
	certs, _ := filepath.Glob(filepath.Join(mspDir, "signcerts", "*.pem"))
	if len(certs) == 0 {
		fatal("signcerts/*.pem introuvable: " + mspDir)
	}
	pemBytes, err := os.ReadFile(certs[0])
	must(err, "lecture signcert")
	cert, err := identity.CertificateFromPEM(pemBytes)
	must(err, "parse signcert")
	id, err := identity.NewX509Identity(mspID, cert)
	must(err, "identité X509")
	return id
}

func loadSign(mspDir string) identity.Sign {
	keys, _ := filepath.Glob(filepath.Join(mspDir, "keystore", "*"))
	if len(keys) == 0 {
		fatal("keystore introuvable: " + mspDir)
	}
	pemBytes, err := os.ReadFile(keys[0])
	must(err, "lecture clé")
	pk, err := identity.PrivateKeyFromPEM(pemBytes)
	must(err, "parse clé")
	sign, err := identity.NewPrivateKeySign(pk)
	must(err, "fonction de signature")
	return sign
}

func must(err error, ctx string) {
	if err != nil {
		fatal(ctx + ": " + err.Error())
	}
}

func fatal(m string) {
	fmt.Fprintln(os.Stderr, "erreur: "+m)
	os.Exit(1)
}
