// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {FreelanceEscrow} from "./FreelanceEscrow.sol";

/// @title EscrowFactory
/// @notice Deploys `FreelanceEscrow` instances and keeps an on-chain registry
///         so clients, freelancers, and frontends can enumerate every escrow
///         they are involved in. The caller becomes the client of the escrow
///         they create — the factory never holds funds itself.
contract EscrowFactory {
    event EscrowDeployed(
        address indexed escrow, address indexed client, address indexed freelancer, uint256 totalAmount
    );

    FreelanceEscrow[] public escrows;
    mapping(address => FreelanceEscrow[]) public escrowsForUser;

    /// @notice Create a new escrow with `msg.sender` as the client.
    /// @return escrow The deployed escrow contract.
    function createEscrow(
        address freelancer,
        address arbiter,
        string[] calldata descriptions,
        uint256[] calldata amounts,
        uint256 deadline
    ) external returns (FreelanceEscrow escrow) {
        escrow = new FreelanceEscrow(msg.sender, freelancer, arbiter, descriptions, amounts, deadline);
        escrows.push(escrow);
        escrowsForUser[msg.sender].push(escrow);
        escrowsForUser[freelancer].push(escrow);
        emit EscrowDeployed(address(escrow), msg.sender, freelancer, escrow.totalAmount());
    }

    function escrowCount() external view returns (uint256) {
        return escrows.length;
    }

    function escrowsFor(address user) external view returns (FreelanceEscrow[] memory) {
        return escrowsForUser[user];
    }
}
