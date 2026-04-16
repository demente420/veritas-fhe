// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, euint64, ebool, externalEuint64, externalEbool} from "@fhevm/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/config/ZamaConfig.sol";

/// @title VeritasFHE - Prediction market con apuestas totalmente encriptadas
/// @notice Ni el admin ni otros usuarios pueden ver el monto o lado apostado
contract VeritasFHE is ZamaEthereumConfig {
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
    mapping(uint256 => mapping(address => euint64)) internal userBets;
    mapping(uint256 => mapping(address => ebool)) internal userSide;
    mapping(uint256 => mapping(address => bool)) public hasBet;
    mapping(uint256 => mapping(address => bool)) public claimed;
    uint256 public marketCount;

    event MarketCreated(uint256 indexed marketId, string question);
    event EncryptedBetPlaced(uint256 indexed marketId, address indexed user);
    event MarketResolved(uint256 indexed marketId, uint256 outcome);
    event Claimed(uint256 indexed marketId, address indexed user);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Solo admin");
        _;
    }

    constructor() {
        admin = msg.sender;
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

    /// @notice Apuesta encriptada. amountEnc y sideEnc vienen del cliente ya cifrados
    function bet(
        uint256 marketId,
        externalEuint64 amountEnc,
        externalEbool sideEnc,
        bytes calldata inputProof
    ) external payable {
        Market storage m = markets[marketId];
        require(m.endTime > 0 && block.timestamp < m.endTime, "Mercado cerrado");
        require(!hasBet[marketId][msg.sender], "Ya apostaste");
        require(msg.value > 0, "ETH requerido");

        euint64 amount = FHE.fromExternal(amountEnc, inputProof);
        ebool side = FHE.fromExternal(sideEnc, inputProof);

        // Selecciona monto para YES o NO segun side encriptado, sin revelarlo
        euint64 zero = FHE.asEuint64(0);
        euint64 yesAmount = FHE.select(side, amount, zero);
        euint64 noAmount = FHE.select(side, zero, amount);

        m.totalYes = FHE.add(m.totalYes, yesAmount);
        m.totalNo = FHE.add(m.totalNo, noAmount);

        userBets[marketId][msg.sender] = amount;
        userSide[marketId][msg.sender] = side;
        hasBet[marketId][msg.sender] = true;

        FHE.allowThis(m.totalYes);
        FHE.allowThis(m.totalNo);
        FHE.allowThis(userBets[marketId][msg.sender]);
        FHE.allowThis(userSide[marketId][msg.sender]);
        FHE.allow(userBets[marketId][msg.sender], msg.sender);
        FHE.allow(userSide[marketId][msg.sender], msg.sender);

        emit EncryptedBetPlaced(marketId, msg.sender);
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

    /// @notice Claim encriptado. El payout se computa sin revelar side/amount
    function claim(uint256 marketId) external {
        Market storage m = markets[marketId];
        require(m.resolved, "No resuelto");
        require(!claimed[marketId][msg.sender], "Ya reclamaste");
        require(hasBet[marketId][msg.sender], "No apostaste");

        claimed[marketId][msg.sender] = true;

        // userWon = (outcome==1 && side) || (outcome==2 && !side)
        ebool side = userSide[marketId][msg.sender];
        ebool userWon = m.finalOutcome == 1 ? side : FHE.not(side);

        // Si gano, payout = amount, si no payout = 0 (balance encriptado)
        euint64 amount = userBets[marketId][msg.sender];
        euint64 zero = FHE.asEuint64(0);
        euint64 encryptedPayout = FHE.select(userWon, amount, zero);

        FHE.allowThis(encryptedPayout);
        FHE.allow(encryptedPayout, msg.sender);

        emit Claimed(marketId, msg.sender);
        // NOTA: El pago real requiere decryption async por el coprocessor Zama
        // Para este PoC el monto se deja encriptado on-chain para privacidad total
    }
}
