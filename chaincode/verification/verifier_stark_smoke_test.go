package main

import (
	"context"
	"strings"
	"testing"
)

// Smoke tests de la brique B : ils valident l'intégration wasm/wazero/ABI
// SANS vrai receipt (donc sans la brique A). Ils prouvent que le .wasm est
// embarqué, que wazero le charge, que les imports WASI se résolvent, que
// _initialize s'exécute, que les fonctions exportées existent, et que la
// plomberie mémoire (alloc -> write -> verify -> code de retour) circule.
//
// À placer dans chaincode/verification/ (package main).
// Lancer : go test -run Smoke -v

func TestSmokeVerifierLoads(t *testing.T) {
	ctx := context.Background()
	v, err := NewWasmVerifier(ctx)
	if err != nil {
		t.Fatalf("le module WASM ne se charge pas dans wazero: %v", err)
	}
	defer v.Close(ctx)
	t.Log("module WASM chargé ; exports présents (alloc/verify/journal_*)")
}

func TestSmokeGarbageReceiptRejected(t *testing.T) {
	ctx := context.Background()
	v, err := NewWasmVerifier(ctx)
	if err != nil {
		t.Fatalf("init verifier: %v", err)
	}
	defer v.Close(ctx)

	// "receipt" bidon + image id de la bonne longueur (32 octets).
	garbage := make([]byte, 512)
	for i := range garbage {
		garbage[i] = byte(i * 7)
	}
	imageID := make([]byte, 32)

	ok, journal, err := v.VerifyProof(ctx, garbage, imageID)
	if ok {
		t.Fatal("un receipt bidon a été ACCEPTÉ — plomberie ou vérif cassée")
	}
	if journal != nil {
		t.Fatalf("journal non nil sur échec: len=%d", len(journal))
	}
	// Un "appel verify: ..." signalerait un trap wasm (plomberie cassée). Une
	// erreur de décodage borsh (ou un simple invalide) confirme l'aller-retour.
	if err != nil && strings.Contains(err.Error(), "appel verify") {
		t.Fatalf("trap wasm au lieu d'un rejet propre — plomberie cassée: %v", err)
	}
	t.Logf("receipt bidon rejeté proprement (err=%v) — aller-retour ABI OK", err)
}

func TestSmokeBadImageIDLength(t *testing.T) {
	ctx := context.Background()
	v, err := NewWasmVerifier(ctx)
	if err != nil {
		t.Fatalf("init verifier: %v", err)
	}
	defer v.Close(ctx)

	ok, _, err := v.VerifyProof(ctx, make([]byte, 64), make([]byte, 5)) // image id trop court
	if ok || err == nil {
		t.Fatalf("image id de 5 octets aurait dû être rejeté (ok=%v, err=%v)", ok, err)
	}
	t.Logf("image id invalide rejeté (err=%v)", err)
}
