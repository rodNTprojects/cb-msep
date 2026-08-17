package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

// Attestation lives in CC_V's OWN namespace. Its presence means "attested".
// Phase 4: adds a deterministic accountability trail (submitter + proof digest).
// The endorser/verifier identities are NOT written — they are carried by the
// block's endorsement signatures (auditable), keeping the write set deterministic.
type Attestation struct {
	Key         string `json:"key"`
	Commitment  string `json:"commitment"`
	Status      string `json:"status"`
	SubmittedBy string `json:"submittedBy"` // tx submitter identity (deterministic across endorsers)
	ProofDigest string `json:"proofDigest"` // sha256(proofHex), for accountability
}

// Verifier abstracts the sigma (binding) and proof checks.
// Wired in Phase 3: VerifyBinding = brique C (ECDSA/MSP), VerifyProof = brique B (WASM/wazero).
type Verifier interface {
	VerifyBinding(key, commitmentHex, sigmaHex string) (bool, error)
	VerifyProof(commitmentHex, proofHex, publicInHex string) (bool, error)
}

type VerificationContract struct {
	contractapi.Contract
	v Verifier
}

// mustVerifier() (verifier_wire.go) builds the real verifier and panics at
// startup if pinned material is missing — fail-closed, never the notWired stub.
func newVerificationContract() *VerificationContract {
	return &VerificationContract{v: mustVerifier()}
}

// Attest = TX2 (non-member-endorsed). Args are public; D is never present.
func (c *VerificationContract) Attest(ctx contractapi.TransactionContextInterface, key, commitmentHex, sigmaHex, proofHex, publicInHex string) error {
	if raw, _ := ctx.GetStub().GetState(key); raw != nil {
		return fmt.Errorf("already attested: %s", key) // idempotency (own namespace)
	}
	ok, err := c.v.VerifyBinding(key, commitmentHex, sigmaHex)
	if err != nil || !ok {
		return fmt.Errorf("binding rejected: %v", err)
	}
	ok, err = c.v.VerifyProof(commitmentHex, proofHex, publicInHex)
	if err != nil || !ok {
		return fmt.Errorf("proof rejected: %v", err)
	}

	// Accountability trail (deterministic): who submitted + which proof.
	submitter, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("client identity: %w", err)
	}
	sum := sha256.Sum256([]byte(proofHex))

	att := Attestation{
		Key:         key,
		Commitment:  commitmentHex,
		Status:      "attested",
		SubmittedBy: submitter,
		ProofDigest: hex.EncodeToString(sum[:]),
	}
	b, err := json.Marshal(att)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, b) // deterministic write set, CC_V namespace
}

func (c *VerificationContract) ReadAttestation(ctx contractapi.TransactionContextInterface, key string) (*Attestation, error) {
	raw, err := ctx.GetStub().GetState(key)
	if err != nil {
		return nil, err
	}
	if raw == nil {
		return nil, fmt.Errorf("not attested: %s", key)
	}
	var a Attestation
	if err := json.Unmarshal(raw, &a); err != nil {
		return nil, err
	}
	return &a, nil
}

// notWired: explicit failure, kept as a documented fallback. No longer injected.
type notWired struct{}

func (notWired) VerifyBinding(_, _, _ string) (bool, error) {
	return false, fmt.Errorf("sigma verifier not wired")
}
func (notWired) VerifyProof(_, _, _ string) (bool, error) {
	return false, fmt.Errorf("proof verifier not wired")
}

func main() {
	cc, err := contractapi.NewChaincode(newVerificationContract())
	if err != nil {
		panic(err)
	}
	if err := cc.Start(); err != nil {
		panic(err)
	}
}
