// sign_binding — outil membre (brique D) : produit le blob sigmaHex à passer à
// Attest. Chaque membre signe CBMSEP-BIND-v1|<key>|<commitmentHex> avec sa clé
// MSP (ECDSA), et on assemble hex(JSON).
//
// Usage :
//   go run . <key> <commitmentHex> <MSPID=mspDir> [<MSPID=mspDir> ...]
// Exemple :
//   go run . asset1 a353c9... \
//     Org1MSP=organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp \
//     Org2MSP=organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp
package main

import (
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const bindingDomain = "CBMSEP-BIND-v1"

type sigEntry struct {
	MSPID string `json:"mspid"`
	Cert  string `json:"cert"`
	Sig   string `json:"sig"`
}

type bindingProof struct {
	V    int        `json:"v"`
	Sigs []sigEntry `json:"sigs"`
}

func main() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "usage: sign_binding <key> <commitmentHex> <MSPID=mspDir> [MSPID=mspDir ...]")
		os.Exit(2)
	}
	key := os.Args[1]
	commitmentHex := os.Args[2]
	digest := sha256.Sum256([]byte(bindingDomain + "|" + key + "|" + commitmentHex))

	bp := bindingProof{V: 1}
	for _, arg := range os.Args[3:] {
		parts := strings.SplitN(arg, "=", 2)
		if len(parts) != 2 {
			fatal("argument invalide (attendu MSPID=mspDir): " + arg)
		}
		mspid, mspDir := parts[0], parts[1]
		certPEM, priv := loadMSP(mspDir)
		sig, err := ecdsa.SignASN1(rand.Reader, priv, digest[:])
		if err != nil {
			fatal("signature: " + err.Error())
		}
		bp.Sigs = append(bp.Sigs, sigEntry{
			MSPID: mspid,
			Cert:  string(certPEM),
			Sig:   base64.StdEncoding.EncodeToString(sig),
		})
	}

	j, err := json.Marshal(bp)
	if err != nil {
		fatal(err.Error())
	}
	fmt.Println(hex.EncodeToString(j)) // = sigmaHex
}

func loadMSP(mspDir string) (certPEM []byte, priv *ecdsa.PrivateKey) {
	certs, _ := filepath.Glob(filepath.Join(mspDir, "signcerts", "*.pem"))
	if len(certs) == 0 {
		fatal("signcerts/*.pem introuvable dans " + mspDir)
	}
	var err error
	certPEM, err = os.ReadFile(certs[0])
	if err != nil {
		fatal(err.Error())
	}

	keys, _ := filepath.Glob(filepath.Join(mspDir, "keystore", "*"))
	if len(keys) == 0 {
		fatal("keystore introuvable dans " + mspDir)
	}
	keyPEM, err := os.ReadFile(keys[0])
	if err != nil {
		fatal(err.Error())
	}
	blk, _ := pem.Decode(keyPEM)
	if blk == nil {
		fatal("clé PEM invalide dans " + mspDir)
	}
	k, err := x509.ParsePKCS8PrivateKey(blk.Bytes)
	if err != nil {
		fatal("clé (PKCS8): " + err.Error())
	}
	var ok bool
	priv, ok = k.(*ecdsa.PrivateKey)
	if !ok {
		fatal("la clé n'est pas ECDSA")
	}
	return certPEM, priv
}

func fatal(m string) {
	fmt.Fprintln(os.Stderr, "erreur: "+m)
	os.Exit(1)
}
