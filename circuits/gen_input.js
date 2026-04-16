const { buildPoseidon } = require("circomlibjs");

async function main() {
    const poseidon = await buildPoseidon();
    const F = poseidon.F;

    const nullifier = 987654321n;
    const secret = 111111111n;
    const recipient = "0xbF0B95320A5F5CE536Bdab452319BbfA58991cBE";

    const commitment = F.toObject(poseidon([nullifier, secret]));
    const nullifierHash = F.toObject(poseidon([nullifier]));

    // Merkle tree vacío: hoja = commitment, todos los hermanos = 0
    // root = hash(hash(...hash(commitment, 0)...), 0) 20 veces
    let current = commitment;
    for (let i = 0; i < 20; i++) {
        current = F.toObject(poseidon([current, 0n]));
    }
    const root = current;

    const input = {
        root: root.toString(),
        nullifierHash: nullifierHash.toString(),
        recipient: BigInt(recipient).toString(),
        nullifier: nullifier.toString(),
        secret: secret.toString(),
        pathElements: Array(20).fill("0"),
        pathIndices: Array(20).fill(0)
    };

    require("fs").writeFileSync("input.json", JSON.stringify(input, null, 2));
    console.log("Input generado. Commitment:", commitment.toString());
    console.log("Root:", root.toString());
}
main().catch(console.error);
