// Câblage : compose la brique C (VerifyBinding) et la brique B (VerifyProof
// via WASM/wazero), et implémente l'interface Verifier attendue par CC_V.
package main

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/hex"
	"fmt"
)

// Image id du guest attendu, épinglé dans CC_V (déposé par le script de refresh
// depuis testdata/imageid.bin). La preuve doit provenir de CE programme.
//
//go:embed expected_imageid.bin
var expectedImageID []byte

// cbmsepVerifier implémente Verifier : VerifyBinding + VerifyProof.
type cbmsepVerifier struct {
	wasm    *WasmVerifier
	binding *memberBinding
	imageID []byte
}

// mustVerifier construit le vérifieur réel ; panique au démarrage du chaincode
// si un élément manque (fail-closed : jamais de stub silencieusement accepté).
func mustVerifier() Verifier {
	v, err := newCBMSEPVerifier()
	if err != nil {
		panic(fmt.Sprintf("init verifier: %v", err))
	}
	return v
}

func newCBMSEPVerifier() (*cbmsepVerifier, error) {
	if len(expectedImageID) != 32 {
		return nil, fmt.Errorf("expected_imageid.bin doit faire 32 octets, obtenu %d", len(expectedImageID))
	}
	wasm, err := NewWasmVerifier(context.Background())
	if err != nil {
		return nil, fmt.Errorf("wasm verifier: %w", err)
	}
	binding, err := newMemberBinding()
	if err != nil {
		return nil, fmt.Errorf("member binding: %w", err)
	}
	return &cbmsepVerifier{wasm: wasm, binding: binding, imageID: expectedImageID}, nil
}

func (v *cbmsepVerifier) VerifyBinding(key, commitmentHex, sigmaHex string) (bool, error) {
	return v.binding.VerifyBinding(key, commitmentHex, sigmaHex)
}

// VerifyProof valide le STARK ET soude la preuve au C revendiqué :
//   - hex(journal[:32]) == commitmentHex   (proof liée au bon C)
//   - journal[32:] == decode(publicInHex)  (bornes min/max déclarées)
func (v *cbmsepVerifier) VerifyProof(commitmentHex, proofHex, publicInHex string) (bool, error) {
	receipt, err := hex.DecodeString(proofHex)
	if err != nil {
		return false, fmt.Errorf("proofHex invalide: %w", err)
	}
	ok, journal, err := v.wasm.VerifyProof(context.Background(), receipt, v.imageID)
	if err != nil {
		return false, err
	}
	if !ok {
		return false, nil // preuve invalide
	}
	if len(journal) < 32 {
		return false, fmt.Errorf("journal trop court: %d octets", len(journal))
	}
	if hex.EncodeToString(journal[:32]) != commitmentHex {
		return false, fmt.Errorf("le C du journal ne correspond pas au commitment")
	}
	if publicInHex != "" {
		pin, err := hex.DecodeString(publicInHex)
		if err != nil {
			return false, fmt.Errorf("publicInHex invalide: %w", err)
		}
		if len(journal) < 32+len(pin) || !bytes.Equal(journal[32:32+len(pin)], pin) {
			return false, fmt.Errorf("entrées publiques (min/max) non conformes")
		}
	}
	return true, nil
}
