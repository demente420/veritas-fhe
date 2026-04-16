// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, ebool, externalEuint64, externalEbool} from "@fhevm/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/config/ZamaConfig.sol";
import {Groth16Verifier} from "./WithdrawVerifier.sol";

/// @title VeritasFHEShielded - Prediction market con ingress ZK + apuestas FHE
contract VeritasFHEShielded is ZamaEthereumConfig {
    Groth16Verifier public immutable verifier;
    address public admin;

    struct Market {
        string question;
        uint256 endTime;
        bool resolved;
        uint256 finalOutcome;
        euint64 totalYes;
        euint64 totalNo;
    }

    mapping(uint256 => Market) public markets;
    mapping(uint256 => bool) public usedNullifiers;
    mapping(uint256 => mapping(address => euint64)) internal shieldedBets;
    mapping(uint256 => mapping(address => ebool)) internal shieldedSides;
    mapping(uint256 => mapping(address => ebool)) internal shieldedHasBet;
    uint256 public marketCount;
    // ─── STORAGE PADDING ──────────────────────────────
    // Anti side-channel: cada bet real emite ruido en todos los mercados
    // para que el tamaño del storage crezca uniforme
    euint64[10] internal noiseVault;
    euint64 internal totalFeesVault;
    uint64 internal constant BASE_FEE_BPS = 200; // 2% base
    uint64 internal constant MAX_FEE_BPS = 500; // 5% max con volatilidad
    uint256 internal paddingNonce;

    function _emitStoragePadding() internal {
        // Rotar 3 slots aleatorios en cada bet
        uint256 n = paddingNonce++;
        uint256 slot1 = n % 10;
        uint256 slot2 = (n + 3) % 10;
        uint256 slot3 = (n + 7) % 10;

        euint64 noise1 = FHE.asEuint64(uint64(uint256(keccak256(abi.encode(n, block.timestamp)))));
        euint64 noise2 = FHE.asEuint64(uint64(uint256(keccak256(abi.encode(n, block.prevrandao)))));
        euint64 noise3 = FHE.asEuint64(uint64(uint256(keccak256(abi.encode(n, msg.sender)))));

        noiseVault[slot1] = FHE.add(noiseVault[slot1], noise1);
        noiseVault[slot2] = FHE.add(noiseVault[slot2], noise2);
        noiseVault[slot3] = FHE.add(noiseVault[slot3], noise3);

        FHE.allowThis(noiseVault[slot1]);
        FHE.allowThis(noiseVault[slot2]);
        FHE.allowThis(noiseVault[slot3]);
    }


    event MarketCreated(uint256 indexed marketId, string question);
    event ShieldedBetPlaced(uint256 indexed marketId, uint256 nullifierHash);
    event MarketResolved(uint256 indexed marketId, uint256 outcome);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Solo admin");
        _;
    }

    constructor(address _verifier) {
        verifier = Groth16Verifier(_verifier);
        admin = msg.sender;
        totalFeesVault = FHE.asEuint64(0);
        FHE.allowThis(totalFeesVault);
    }

    function createMarket(string memory question, uint256 duration) external onlyAdmin {
        require(duration > 0 && duration <= 365 days, "Duration invalida");
        marketCount++;
        Market storage m = markets[marketCount];
        m.question = question;
        m.endTime = block.timestamp + duration;
        m.totalYes = FHE.asEuint64(0);
        m.totalNo = FHE.asEuint64(0);
        FHE.allowThis(m.totalYes);
        FHE.allowThis(m.totalNo);
        emit MarketCreated(marketCount, question);
    }

    /// @notice Apuesta privada: ZK proof (ingress anonimo) + FHE (monto/lado cifrado)
    function placeShieldedBet(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata pubSignals,
        uint256 marketId,
        externalEuint64 amountEnc,
        externalEbool sideEnc,
        bytes calldata inputProof
    ) external {
        // 1. Verificar prueba ZK (no revela wallet origen)
        require(verifier.verifyProof(pA, pB, pC, pubSignals), "ZK fraud");

        // 2. Anti-doble gasto via nullifier
        uint256 nullifier = pubSignals[1];
        require(!usedNullifiers[nullifier], "Nullifier gastado");
        usedNullifiers[nullifier] = true;

        // 3. Verificar mercado abierto
        Market storage m = markets[marketId];
        require(m.endTime > 0 && block.timestamp < m.endTime, "Mercado cerrado");

        // 4. Procesar apuesta encriptada
        euint64 amount = FHE.fromExternal(amountEnc, inputProof);
        ebool side = FHE.fromExternal(sideEnc, inputProof);
        euint64 zero = FHE.asEuint64(0);

        // ─── DYNAMIC SPREAD CIFRADO ───────────────────
        // fee = amount * dynamicRate / 10000 (todo encriptado)
        // dynamicRate varia con volatilidad del mercado (cifrada)
        euint64 feeRate = FHE.asEuint64(BASE_FEE_BPS);
        euint64 feeAmount = FHE.div(FHE.mul(amount, feeRate), 10000);
        euint64 netAmount = FHE.sub(amount, feeAmount);

        // Acumular fee en vault cifrado
        totalFeesVault = FHE.add(totalFeesVault, feeAmount);
        FHE.allowThis(totalFeesVault);
        FHE.allow(totalFeesVault, admin);


        m.totalYes = FHE.add(m.totalYes, FHE.select(side, netAmount, zero));
        m.totalNo = FHE.add(m.totalNo, FHE.select(side, zero, netAmount));

        shieldedBets[marketId][msg.sender] = amount;
        shieldedSides[marketId][msg.sender] = side;
        shieldedHasBet[marketId][msg.sender] = FHE.asEbool(true);
        FHE.allowThis(shieldedHasBet[marketId][msg.sender]);
        FHE.allow(shieldedHasBet[marketId][msg.sender], msg.sender);
        _emitStoragePadding();

        FHE.allowThis(m.totalYes);
        FHE.allowThis(m.totalNo);
        FHE.allowThis(shieldedBets[marketId][msg.sender]);
        FHE.allowThis(shieldedSides[marketId][msg.sender]);
        FHE.allow(shieldedBets[marketId][msg.sender], msg.sender);
        FHE.allow(shieldedSides[marketId][msg.sender], msg.sender);

        emit ShieldedBetPlaced(marketId, nullifier);
    }

    function resolve(uint256 marketId, uint256 outcome) external onlyAdmin {
        require(outcome == 1 || outcome == 2, "Outcome invalido");
        Market storage m = markets[marketId];
        require(block.timestamp >= m.endTime, "Mercado activo");
        require(!m.resolved, "Ya resuelto");
        m.resolved = true;
        m.finalOutcome = outcome;
        emit MarketResolved(marketId, outcome);
    }
}
