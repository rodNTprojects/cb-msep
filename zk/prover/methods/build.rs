fn main() {
    // Compile methods/guest et écrit methods.rs (PREDICATE_ELF, PREDICATE_ID)
    // dans OUT_DIR. Utilise le toolchain risc0 installé (rzup).
    risc0_build::embed_methods();
}
