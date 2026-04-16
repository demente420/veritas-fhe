// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {VeritasFHE} from "../src/VeritasFHE.sol";

contract DeployVeritasFHE is Script {
    function run() external {
        vm.startBroadcast();
        VeritasFHE fhe = new VeritasFHE();
        console.log("VeritasFHE:", address(fhe));
        vm.stopBroadcast();
    }
}
