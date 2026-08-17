package main

import (
	"context"
	"encoding/hex"
	"os"
	"testing"
)

// Teste le VerifyProof CÂBLÉ : validation STARK (WASM) + soudure au commitment.
// Nécessite le matériel épinglé (member_roots + expected_imageid + verifier.wasm)
// et un receipt réel (brique A) dans testdata/.
func TestWiredVerifyProofBindsCommitment(t *testing.T) {
	receipt, err := os.ReadFile("testdata/receipt.bin")
	if err != nil {
		t.Skip("testdata/receipt.bin absent — lance la brique A (zk/prover host)")
	}
	proofHex := hex.EncodeToString(receipt)

	// Valeurs attendues (Phase 2 / brique A) :
	const commitment = "a353c969452b888a5e3e1ba25e1bb783461898070de580e482cf8c8e8414fc53"
	const publicIn = "f049020000000000e093040000000000" // min=150000, max=300000 (u64 LE)

	v, err := newCBMSEPVerifier()
	if err != nil {
		t.Fatalf("construction du vérifieur (matériel épinglé manquant ?): %v", err)
	}
	defer v.wasm.Close(context.Background())

	// Preuve correcte + bon commitment -> acceptée.
	ok, err := v.VerifyProof(commitment, proofHex, publicIn)
	if err != nil || !ok {
		t.Fatalf("preuve correcte refusée: ok=%v err=%v", ok, err)
	}

	// Bon STARK mais commitment falsifié -> doit être refusé (soudure C).
	badCommitment := "00" + commitment[2:]
	ok, err = v.VerifyProof(badCommitment, proofHex, publicIn)
	if ok {
		t.Fatal("preuve ACCEPTÉE pour un mauvais commitment — soudure journal<->C cassée")
	}
	t.Logf("soudure OK : bon C accepté, mauvais C refusé (err=%v)", err)

	// Bornes publiques falsifiées -> refusé.
	ok, _ = v.VerifyProof(commitment, proofHex, "0000000000000000e093040000000000")
	if ok {
		t.Fatal("preuve ACCEPTÉE avec des bornes min/max falsifiées")
	}
}
