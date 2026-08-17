// Brique C — VerifyBinding : signature de seuil des membres sur (key, C),
// vérifiée en ECDSA contre les racines CA membres épinglées.
//
// Déterminisme (consensus) : autorisation par cert.CheckSignatureFrom (émission
// par la racine, PAS de contrôle d'horloge), signature par ecdsa.VerifyASN1.
// On n'utilise jamais x509.Verify (qui appelle time.Now()).
package main

import (
	"crypto/ecdsa"
	"crypto/sha256"
	"crypto/x509"
	"embed"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"strings"
)

// requiredMembers : nombre de membres distincts devant signer (seuil t).
const requiredMembers = 2

// bindingDomain : étiquette de séparation de domaine (cf. doc brique C).
const bindingDomain = "CBMSEP-BIND-v1"

// Racines CA des membres, déposées par scripts/refresh_binding_material.sh
// sous member_roots/<MSPID>.pem AVANT le packaging de CC_V.
//
//go:embed member_roots/*.pem
var memberRootsFS embed.FS

// Contenu transporté dans sigmaHex = hex(JSON de bindingProof).
type sigEntry struct {
	MSPID string `json:"mspid"`
	Cert  string `json:"cert"` // PEM du certificat du signataire
	Sig   string `json:"sig"`  // base64 de la signature ECDSA (ASN.1 DER)
}

type bindingProof struct {
	V    int        `json:"v"`
	Sigs []sigEntry `json:"sigs"`
}

type memberBinding struct {
	roots map[string]*x509.Certificate // MSPID -> racine CA épinglée
}

func newMemberBinding() (*memberBinding, error) {
	entries, err := memberRootsFS.ReadDir("member_roots")
	if err != nil {
		return nil, fmt.Errorf("member_roots: %w", err)
	}
	roots := make(map[string]*x509.Certificate)
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".pem") {
			continue
		}
		mspid := strings.TrimSuffix(e.Name(), ".pem") // convention : <MSPID>.pem
		raw, err := memberRootsFS.ReadFile("member_roots/" + e.Name())
		if err != nil {
			return nil, err
		}
		cert, err := parsePEMCert(raw)
		if err != nil {
			return nil, fmt.Errorf("racine %s: %w", e.Name(), err)
		}
		roots[mspid] = cert
	}
	if len(roots) == 0 {
		return nil, fmt.Errorf("aucune racine membre embarquée (member_roots vide)")
	}
	return &memberBinding{roots: roots}, nil
}

func (b *memberBinding) VerifyBinding(key, commitmentHex, sigmaHex string) (bool, error) {
	digest := sha256.Sum256([]byte(bindingDomain + "|" + key + "|" + commitmentHex))

	raw, err := hex.DecodeString(sigmaHex)
	if err != nil {
		return false, fmt.Errorf("sigmaHex invalide: %w", err)
	}
	var bp bindingProof
	if err := json.Unmarshal(raw, &bp); err != nil {
		return false, fmt.Errorf("payload binding invalide: %w", err)
	}

	seen := make(map[string]bool) // dédup par organisation membre
	for _, s := range bp.Sigs {
		root, ok := b.roots[s.MSPID]
		if !ok {
			continue // mspid non membre
		}
		cert, err := parsePEMCert([]byte(s.Cert))
		if err != nil {
			continue
		}
		// Autorisation DÉTERMINISTE : émis par la racine membre, sans time.Now.
		if err := cert.CheckSignatureFrom(root); err != nil {
			continue
		}
		pub, ok := cert.PublicKey.(*ecdsa.PublicKey)
		if !ok {
			continue
		}
		sig, err := base64.StdEncoding.DecodeString(s.Sig)
		if err != nil {
			continue
		}
		if !ecdsa.VerifyASN1(pub, digest[:], sig) {
			continue
		}
		seen[s.MSPID] = true
	}
	return len(seen) >= requiredMembers, nil
}

func parsePEMCert(pemBytes []byte) (*x509.Certificate, error) {
	blk, _ := pem.Decode(pemBytes)
	if blk == nil {
		return nil, fmt.Errorf("PEM invalide")
	}
	return x509.ParseCertificate(blk.Bytes)
}
