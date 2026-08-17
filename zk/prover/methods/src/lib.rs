// Injecte les constantes générées par build.rs : PREDICATE_ELF, PREDICATE_ID.
include!(concat!(env!("OUT_DIR"), "/methods.rs"));
