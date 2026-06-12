fn main() {
    uniffi::generate_scaffolding("src/hdri_encoder.udl").expect("failed to generate UniFFI scaffolding");
}

