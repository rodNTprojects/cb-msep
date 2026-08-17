package main

import (
	"context"
	"encoding/hex"
	"os"
	"testing"
)

// Le module WASM vient de //go:embed (verifier.wasm doit exister pour compiler).
// Les receipts de test viennent de la brique A (host) :
//   - testdata/receipt.bin  (receipt sérialisé borsh)
//   - testdata/imageid.bin  (32 octets = Digest::as_bytes)
// Le verdict WASM doit égaler le verdict natif du host : test d'équivalence.

func TestVerifyEquivalence(t *testing.T) {
	receipt, err := os.ReadFile("testdata/receipt.bin")
	if err != nil {
		t.Skip("testdata/receipt.bin absent — génère-le via la brique A (host)")
	}
	imageID, err := os.ReadFile("testdata/imageid.bin")
	if err != nil {
		t.Skip("testdata/imageid.bin absent — génère-le via la brique A (host)")
	}
	if len(imageID) != 32 {
		t.Fatalf("image id doit faire 32 octets, obtenu %d", len(imageID))
	}

	ctx := context.Background()
	v, err := NewWasmVerifier(ctx)
	if err != nil {
		t.Fatalf("init verifier: %v", err)
	}
	defer v.Close(ctx)

	ok, journal, err := v.VerifyProof(ctx, receipt, imageID)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if !ok {
		t.Fatal("preuve jugée INVALIDE en WASM — attendu valide (désaccord avec le natif)")
	}
	t.Logf("WASM verdict = VALIDE ; journal (%d octets) = %s",
		len(journal), hex.EncodeToString(journal))
}

func TestRejectsTamperedReceipt(t *testing.T) {
	receipt, err := os.ReadFile("testdata/receipt.bin")
	if err != nil {
		t.Skip("testdata/receipt.bin absent")
	}
	imageID, err := os.ReadFile("testdata/imageid.bin")
	if err != nil || len(imageID) != 32 {
		t.Skip("testdata/imageid.bin absent ou invalide")
	}

	if len(receipt) > 100 {
		receipt[len(receipt)/2] ^= 0xFF // corrompt un octet
	}

	ctx := context.Background()
	v, err := NewWasmVerifier(ctx)
	if err != nil {
		t.Fatalf("init verifier: %v", err)
	}
	defer v.Close(ctx)

	ok, _, err := v.VerifyProof(ctx, receipt, imageID)
	if ok {
		t.Fatal("un receipt corrompu a été ACCEPTÉ — faille de sécurité")
	}
	t.Logf("receipt corrompu correctement rejeté (ok=%v, err=%v)", ok, err)
}
