// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VeritasFHEShielded} from "../src/VeritasFHEShielded.sol";
import {Groth16Verifier} from "../src/WithdrawVerifier.sol";

contract DeployShielded is Script {
    function run() external {
        vm.startBroadcast();
        Groth16Verifier verifier = new Groth16Verifier();
        console.log("Verifier:", address(verifier));
        VeritasFHEShielded shielded = new VeritasFHEShielded(address(verifier));
        console.log("VeritasFHEShielded:", address(shielded));
        vm.stopBroadcast();
    }
}
