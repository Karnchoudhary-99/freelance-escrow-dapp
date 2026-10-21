// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

/// @notice Deploy the EscrowFactory to a local Anvil node or a testnet.
/// @dev Usage:
///   anvil & forge script script/Deploy.s.sol --broadcast \
///     --rpc-url http://127.0.0.1:8545
///   The factory itself holds no funds; escrows are created per-client
///   via `EscrowFactory.createEscrow` (see README demo walkthrough).
contract Deploy is Script {
    function run() external returns (EscrowFactory factory) {
        vm.startBroadcast();
        factory = new EscrowFactory();
        vm.stopBroadcast();
        console.log("EscrowFactory deployed at:", address(factory));
    }
}
