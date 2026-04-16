pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/switcher.circom";

// Sub-circuito para el Merkle Tree
template MerkleTreeChecker(levels) {
    signal input leaf;
    signal input root;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    component hashers[levels];
    component multiplexers[levels];

    signal levelHashes[levels + 1];
    levelHashes[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        hashers[i] = Poseidon(2);
        multiplexers[i] = Switcher();
        
        multiplexers[i].L <== levelHashes[i];
        multiplexers[i].R <== pathElements[i];
        multiplexers[i].sel <== pathIndices[i];

        hashers[i].inputs[0] <== multiplexers[i].outL;
        hashers[i].inputs[1] <== multiplexers[i].outR;

        levelHashes[i + 1] <== hashers[i].out;
    }

    root === levelHashes[levels];
}

// Circuito Principal
template VeritasNullifier(levels) {
    // Inputs Públicos (Lo que ve el Smart Contract)
    signal input root;
    signal input nullifierHash;

    // Inputs Privados (Lo que solo tú y tu API Rust saben)
    signal input secret;
    signal input salt;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // 1. Verificamos que el Nullifier Hash corresponde al secreto
    component nHasher = Poseidon(1);
    nHasher.inputs[0] <== secret;
    nHasher.out === nullifierHash;

    // 2. Generamos la "Moneda" (Leaf)
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== secret;
    commitmentHasher.inputs[1] <== salt;

    // 3. Verificamos que la Moneda existe en el Merkle Tree del contrato
    component tree = MerkleTreeChecker(levels);
    tree.leaf <== commitmentHasher.out;
    tree.root <== root;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }
}

// Instanciamos el Mixer con 20 niveles (capacidad: 1,048,576 depósitos)
component main {public [root, nullifierHash]} = VeritasNullifier(20);
