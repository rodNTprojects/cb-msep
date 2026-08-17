// Fichier du chaincode de vérification CC_V (package main, comme
// verification_contract.go — un chaincode Fabric est un exécutable).
//
// Exécute le vérifieur RISC Zero (compilé en WASM) dans wazero — runtime WASM
// en Go pur, donc AUCUN cgo n'est lié au chaincode. Le module .wasm est
// embarqué dans le binaire via //go:embed : il part avec le package lors du
// `peer lifecycle chaincode package`, et l'invariant « CC_V n'a pas d'API de
// lecture privée » reste intact (on ne fait que vérifier signature et preuve).
//
// Câblage : dans newVerificationContract(), remplacer le stub notWired{} par
// une instance qui délègue VerifyProof à ce WasmVerifier. VerifyBinding (σ)
// reste la brique C.
package main

import (
	"context"
	_ "embed"
	"fmt"
	"sync"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
	"github.com/tetratelabs/wazero/imports/wasi_snapshot_preview1"
)

//go:embed verifier.wasm
var verifierWasm []byte

// WasmVerifier tient l'instance wazero et les fonctions exportées du module.
// Compilé/instancié une fois, réutilisé à chaque appel ; un mutex sérialise
// les appels car une instance wazero n'est pas sûre en accès concurrent et
// Fabric peut invoquer le chaincode en parallèle.
type WasmVerifier struct {
	mu       sync.Mutex
	runtime  wazero.Runtime
	module   api.Module
	alloc    api.Function
	dealloc  api.Function
	verify   api.Function
	journalP api.Function
	journalL api.Function
}

// NewWasmVerifier compile et instancie le module WASM embarqué.
func NewWasmVerifier(ctx context.Context) (*WasmVerifier, error) {
	r := wazero.NewRuntime(ctx)

	// Le module cible wasm32-wasip1 : il importe wasi_snapshot_preview1.
	if _, err := wasi_snapshot_preview1.Instantiate(ctx, r); err != nil {
		_ = r.Close(ctx)
		return nil, fmt.Errorf("instancier WASI: %w", err)
	}

	// Pas de démarrage automatique (le reactor n'a pas de _start) ; on appelle
	// _initialize à la main s'il existe.
	cfg := wazero.NewModuleConfig().WithStartFunctions()
	mod, err := r.InstantiateWithConfig(ctx, verifierWasm, cfg)
	if err != nil {
		_ = r.Close(ctx)
		return nil, fmt.Errorf("instancier le module: %w", err)
	}
	if initFn := mod.ExportedFunction("_initialize"); initFn != nil {
		if _, err := initFn.Call(ctx); err != nil {
			_ = r.Close(ctx)
			return nil, fmt.Errorf("_initialize: %w", err)
		}
	}

	v := &WasmVerifier{
		runtime:  r,
		module:   mod,
		alloc:    mod.ExportedFunction("alloc"),
		dealloc:  mod.ExportedFunction("dealloc"),
		verify:   mod.ExportedFunction("verify"),
		journalP: mod.ExportedFunction("journal_ptr"),
		journalL: mod.ExportedFunction("journal_len"),
	}
	if v.alloc == nil || v.verify == nil || v.journalP == nil || v.journalL == nil {
		_ = r.Close(ctx)
		return nil, fmt.Errorf("exports WASM manquants (alloc/verify/journal_*)")
	}
	return v, nil
}

// Close libère l'instance wazero.
func (v *WasmVerifier) Close(ctx context.Context) error {
	return v.runtime.Close(ctx)
}

// VerifyProof exécute la vérification WASM.
// Retourne (valide, octets du journal, erreur). Le journal porte les sorties
// publiques de la preuve (dont l'engagement C), que l'appelant lie ensuite à
// l'engagement signé par les membres (brique C).
func (v *WasmVerifier) VerifyProof(ctx context.Context, receipt, imageID []byte) (bool, []byte, error) {
	if len(imageID) != 32 {
		return false, nil, fmt.Errorf("image id doit faire 32 octets, obtenu %d", len(imageID))
	}

	v.mu.Lock()
	defer v.mu.Unlock()

	rPtr, err := v.write(ctx, receipt)
	if err != nil {
		return false, nil, err
	}
	defer v.free(ctx, rPtr, len(receipt))

	iPtr, err := v.write(ctx, imageID)
	if err != nil {
		return false, nil, err
	}
	defer v.free(ctx, iPtr, len(imageID))

	res, err := v.verify.Call(ctx,
		uint64(rPtr), uint64(len(receipt)),
		uint64(iPtr), uint64(len(imageID)),
	)
	if err != nil {
		return false, nil, fmt.Errorf("appel verify: %w", err)
	}

	switch int32(res[0]) {
	case 0:
		journal, jerr := v.readJournal(ctx)
		return true, journal, jerr
	case 1:
		return false, nil, nil // preuve invalide, pas une erreur
	case 2:
		return false, nil, fmt.Errorf("échec de décodage borsh du receipt")
	case 3:
		return false, nil, fmt.Errorf("longueur d'image id invalide côté wasm")
	default:
		return false, nil, fmt.Errorf("code de retour WASM inconnu: %d", int32(res[0]))
	}
}

func (v *WasmVerifier) write(ctx context.Context, b []byte) (uint32, error) {
	res, err := v.alloc.Call(ctx, uint64(len(b)))
	if err != nil {
		return 0, fmt.Errorf("alloc: %w", err)
	}
	ptr := uint32(res[0])
	if !v.module.Memory().Write(ptr, b) {
		return 0, fmt.Errorf("écriture mémoire hors limites")
	}
	return ptr, nil
}

func (v *WasmVerifier) free(ctx context.Context, ptr uint32, n int) {
	if v.dealloc != nil {
		_, _ = v.dealloc.Call(ctx, uint64(ptr), uint64(n))
	}
}

func (v *WasmVerifier) readJournal(ctx context.Context) ([]byte, error) {
	lp, err := v.journalL.Call(ctx)
	if err != nil {
		return nil, fmt.Errorf("journal_len: %w", err)
	}
	pp, err := v.journalP.Call(ctx)
	if err != nil {
		return nil, fmt.Errorf("journal_ptr: %w", err)
	}
	view, ok := v.module.Memory().Read(uint32(pp[0]), uint32(lp[0]))
	if !ok {
		return nil, fmt.Errorf("lecture du journal hors limites")
	}
	out := make([]byte, len(view))
	copy(out, view) // copie hors de la mémoire wasm, réécrite au prochain appel
	return out, nil
}
