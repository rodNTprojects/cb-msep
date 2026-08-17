package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/hyperledger/fabric-contract-api-go/contractapi"
)

const collection = "assetPDC"

// Record is the PUBLIC on-ledger record written by CC_D. It never contains D.
type Record struct {
	Key         string `json:"key"`
	Commitment  string `json:"commitment"`
	PredicateID string `json:"predicateId,omitempty" metadata:",optional"`
	Status      string `json:"status"`
}

type DataContract struct{ contractapi.Contract }

// SubmitData = TX1 (member-endorsed). D arrives in the transient field, never as a public arg.
func (c *DataContract) SubmitData(ctx contractapi.TransactionContextInterface, key, predicateID string) error {
	t, err := ctx.GetStub().GetTransient()
	if err != nil {
		return fmt.Errorf("transient: %w", err)
	}
	d, ok := t["data"]
	if !ok || len(d) == 0 {
		return fmt.Errorf("transient key 'data' (D) is required")
	}
	if err := ctx.GetStub().PutPrivateData(collection, key, d); err != nil {
		return fmt.Errorf("PutPrivateData: %w", err)
	}
	sum := sha256.Sum256(d)
	rec := Record{Key: key, Commitment: hex.EncodeToString(sum[:]), PredicateID: predicateID, Status: "pending"}
	b, err := json.Marshal(rec)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, b) // public C reaches the ledger at commit
}

func (c *DataContract) ReadRecord(ctx contractapi.TransactionContextInterface, key string) (*Record, error) {
	raw, err := ctx.GetStub().GetState(key)
	if err != nil {
		return nil, err
	}
	if raw == nil {
		return nil, fmt.Errorf("no record for %s", key)
	}
	var r Record
	if err := json.Unmarshal(raw, &r); err != nil {
		return nil, err
	}
	return &r, nil
}

// Cancel = give-up path (Phase 4), member-endorsed. Explicit business transaction
// (no timer — the chaincode has no reliable wall-clock). Moves a *pending* deed to
// *cancelled*.
//
// Honest limit: CC_D cannot read CC_V, so Cancel acts on CC_D's own view. The
// "only pending" guard prevents cancelling what CC_D still considers open; it
// cannot undo an attestation already written in CC_V's namespace.
func (c *DataContract) Cancel(ctx contractapi.TransactionContextInterface, key string) error {
	raw, err := ctx.GetStub().GetState(key)
	if err != nil {
		return err
	}
	if raw == nil {
		return fmt.Errorf("no record for %s", key)
	}
	var r Record
	if err := json.Unmarshal(raw, &r); err != nil {
		return err
	}
	if r.Status != "pending" {
		return fmt.Errorf("cannot cancel %s: status is %q, not pending", key, r.Status)
	}
	r.Status = "cancelled"
	b, err := json.Marshal(r)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(key, b) // deterministic write set
}

func main() {
	cc, err := contractapi.NewChaincode(&DataContract{})
	if err != nil {
		panic(err)
	}
	if err := cc.Start(); err != nil {
		panic(err)
	}
}
