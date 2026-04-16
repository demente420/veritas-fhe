pragma circom 2.1.6;

include "../node_modules/circomlib/circuits/poseidon.circom";

// Selector de 2 elementos segun bit s (igual a Tornado Cash)
template DualMux() {
    signal input in[2];
    signal input s;
    signal output out[2];
    s * (1 - s) === 0;
    out[0] <== (in[1] - in[0]) * s + in[0];
    out[1] <== (in[0] - in[1]) * s + in[1];
}

// Verifica que leaf esta en el Merkle Tree de root
template MerkleTreeChecker(levels) {
    signal input leaf;
    signal input root;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    component hashers[levels];
    component selectors[levels];
    signal intermediateHashes[levels + 1];
    intermediateHashes[0] <== leaf;

    for (var i = 0; i < levels; i++) {
        selectors[i] = DualMux();
        selectors[i].in[0] <== intermediateHashes[i];
        selectors[i].in[1] <== pathElements[i];
        selectors[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== selectors[i].out[0];
        hashers[i].inputs[1] <== selectors[i].out[1];
        intermediateHashes[i + 1] <== hashers[i].out;
    }

    root === intermediateHashes[levels];
}

template VeritasWithdraw(levels) {
    // PUBLIC: lo que el contrato recibe
    signal input root;
    signal input nullifierHash;
    signal input recipient;

    // PRIVATE: testigo que solo el owner conoce
    signal input nullifier;
    signal input secret;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // 1. CONSTRAINT: Reconstruir commitment = Poseidon(nullifier, secret)
    component commitmentHasher = Poseidon(2);
    commitmentHasher.inputs[0] <== nullifier;
    commitmentHasher.inputs[1] <== secret;

    // 2. CONSTRAINT: nullifierHash publico === Poseidon(nullifier)
    component nullifierHasher = Poseidon(1);
    nullifierHasher.inputs[0] <== nullifier;
    nullifierHasher.out === nullifierHash;

    // 3. CONSTRAINT: commitment esta en el Merkle Tree
    component tree = MerkleTreeChecker(levels);
    tree.leaf <== commitmentHasher.out;
    tree.root <== root;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }

    // 4. ANTI-MALLEABILITY: bind recipient a la prueba
    // Si un atacante cambia recipient, recipientSquared cambia y la prueba falla
    signal recipientSquared;
    recipientSquared <== recipient * recipient;
}

component main {public [root, nullifierHash, recipient]} = VeritasWithdraw(20);
