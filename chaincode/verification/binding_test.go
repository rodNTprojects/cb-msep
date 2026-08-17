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
	"os"
	"path/filepath"
	"testing"
)

// Teste VerifyBinding (brique C) avec de VRAIES identités MSP du réseau, sans
// déploiement. Nécessite : member_roots embarqués (lance refresh_binding_material.sh)
// et organizations/ présent (réseau généré). Sinon, SKIP propre.
//
// À placer dans chaincode/verification/.

const (
	commitmentC = "a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53"
	org1User    = "../../organizations/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp"
	org2User    = "../../organizations/peerOrganizations/org2.example.com/users/User1@org2.example.com/msp"
	org3User    = "../../organizations/peerOrganizations/org3.example.com/users/User1@org3.example.com/msp"
)

// signAs signe CBMSEP-BIND-v1|key|commitment avec la clé MSP de mspDir.
func signAs(t *testing.T, mspid, mspDir, key, commitmentHex string) sigEntry {
	t.Helper()
	digest := sha256.Sum256([]byte(bindingDomain + "|" + key + "|" + commitmentHex))

	certs, _ := filepath.Glob(filepath.Join(mspDir, "signcerts", "*.pem"))
	if len(certs) == 0 {
		t.Skipf("signcerts absent (%s) — réseau généré ?", mspDir)
	}
	certPEM, err := os.ReadFile(certs[0])
	if err != nil {
		t.Fatal(err)
	}
	keys, _ := filepath.Glob(filepath.Join(mspDir, "keystore", "*"))
	if len(keys) == 0 {
		t.Skipf("keystore absent (%s)", mspDir)
	}
	keyPEM, err := os.ReadFile(keys[0])
	if err != nil {
		t.Fatal(err)
	}
	blk, _ := pem.Decode(keyPEM)
	if blk == nil {
		t.Fatal("clé PEM invalide")
	}
	k, err := x509.ParsePKCS8PrivateKey(blk.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	priv := k.(*ecdsa.PrivateKey)
	sig, err := ecdsa.SignASN1(rand.Reader, priv, digest[:])
	if err != nil {
		t.Fatal(err)
	}
	return sigEntry{MSPID: mspid, Cert: string(certPEM), Sig: base64.StdEncoding.EncodeToString(sig)}
}

func blobHex(t *testing.T, entries ...sigEntry) string {
	t.Helper()
	j, err := json.Marshal(bindingProof{V: 1, Sigs: entries})
	if err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(j)
}

func newBindingOrSkip(t *testing.T) *memberBinding {
	t.Helper()
	b, err := newMemberBinding()
	if err != nil {
		t.Skipf("member_roots absent — lance scripts/refresh_binding_material.sh (%v)", err)
	}
	return b
}

// Cas nominal : les deux membres signent -> accepté.
func TestBindingAcceptsTwoMembers(t *testing.T) {
	b := newBindingOrSkip(t)
	s1 := signAs(t, "Org1MSP", org1User, "asset1", commitmentC)
	s2 := signAs(t, "Org2MSP", org2User, "asset1", commitmentC)
	ok, err := b.VerifyBinding("asset1", commitmentC, blobHex(t, s1, s2))
	if err != nil || !ok {
		t.Fatalf("deux membres légitimes refusés: ok=%v err=%v", ok, err)
	}
}

// Un seul membre -> sous le seuil (requiredMembers=2) -> refusé.
func TestBindingRejectsSingleMember(t *testing.T) {
	b := newBindingOrSkip(t)
	s1 := signAs(t, "Org1MSP", org1User, "asset1", commitmentC)
	ok, _ := b.VerifyBinding("asset1", commitmentC, blobHex(t, s1))
	if ok {
		t.Fatal("un seul membre a suffi — seuil non appliqué")
	}
}

// Signature sur un autre commitment -> ne vérifie pas le message présenté.
func TestBindingRejectsWrongMessage(t *testing.T) {
	b := newBindingOrSkip(t)
	otherC := "00" + commitmentC[2:]
	s1 := signAs(t, "Org1MSP", org1User, "asset1", otherC) // signe otherC
	s2 := signAs(t, "Org2MSP", org2User, "asset1", otherC)
	ok, _ := b.VerifyBinding("asset1", commitmentC, blobHex(t, s1, s2)) // vérifie commitmentC
	if ok {
		t.Fatal("signature sur un mauvais message acceptée")
	}
}

// Non-membre (Org3) : mspid hors liste blanche -> non compté ; avec un seul
// membre légitime, on reste sous le seuil -> refusé.
func TestBindingRejectsNonMember(t *testing.T) {
	b := newBindingOrSkip(t)
	s1 := signAs(t, "Org1MSP", org1User, "asset1", commitmentC)
	s3 := signAs(t, "Org3MSP", org3User, "asset1", commitmentC) // Org3 = non-membre
	ok, _ := b.VerifyBinding("asset1", commitmentC, blobHex(t, s1, s3))
	if ok {
		t.Fatal("un non-membre a été compté comme membre")
	}
}

// Usurpation : cert Org3 présenté sous l'étiquette Org2MSP -> CheckSignatureFrom
// contre la racine Org2 échoue -> non compté.
func TestBindingRejectsImpersonation(t *testing.T) {
	b := newBindingOrSkip(t)
	s1 := signAs(t, "Org1MSP", org1User, "asset1", commitmentC)
	imposter := signAs(t, "Org2MSP", org3User, "asset1", commitmentC) // cert Org3, étiquette Org2MSP
	ok, _ := b.VerifyBinding("asset1", commitmentC, blobHex(t, s1, imposter))
	if ok {
		t.Fatal("usurpation acceptée : un cert Org3 est passé pour Org2")
	}
}
