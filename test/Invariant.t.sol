// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

/// @notice Fuzz handler driving one funded escrow through its lifecycle.
/// @dev Every action is guarded to the state it is legal in, so a revert
///      can never mask a broken invariant: if the handler calls the
///      contract, the call is expected to succeed. Actions that are not
///      legal in the current state are no-ops.
contract EscrowHandler is Test {
    FreelanceEscrow public escrow;
    address public client;
    address public freelancer;
    address public arbiter;
    uint256 public deadline;

    constructor(address _client, address _freelancer, address _arbiter) {
        client = _client;
        freelancer = _freelancer;
        arbiter = _arbiter;
        deadline = block.timestamp + 30 days;

        string[] memory descriptions = new string[](3);
        descriptions[0] = "Design mockups";
        descriptions[1] = "Frontend build";
        descriptions[2] = "Deployment + docs";
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        escrow = new FreelanceEscrow(client, freelancer, arbiter, descriptions, amounts, deadline);
        vm.deal(client, 100 ether);
        vm.prank(client);
        escrow.fund{value: 6 ether}();
    }

    function _status() internal view returns (FreelanceEscrow.Status) {
        return escrow.status();
    }

    function submitMilestone(uint256 seed) external {
        if (_status() != FreelanceEscrow.Status.Funded) return;
        uint256 index = seed % 3;
        (,, bool submitted, bool approved) = escrow.milestones(index);
        if (approved) return;
        // Re-submitting an unapproved milestone is legal (idempotent).
        submitted;
        vm.prank(freelancer);
        escrow.submitMilestone(index);
    }

    function approveMilestone(uint256 seed) external {
        if (_status() != FreelanceEscrow.Status.Funded) return;
        uint256 index = seed % 3;
        (,, bool submitted, bool approved) = escrow.milestones(index);
        if (!submitted || approved) return;
        vm.prank(client);
        escrow.approveMilestone(index);
    }

    // __NEXT_ACTIONS__
}
