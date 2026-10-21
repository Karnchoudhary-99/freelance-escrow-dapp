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

    function raiseDispute(uint256 seed) external {
        if (_status() != FreelanceEscrow.Status.Funded) return;
        // Either party may raise; alternate by seed so both are exercised.
        address by = seed % 2 == 0 ? client : freelancer;
        vm.prank(by);
        escrow.raiseDispute("fuzz dispute");
    }

    function resolveDispute(uint256 seed) external {
        if (_status() != FreelanceEscrow.Status.Disputed) return;
        uint256 remaining = escrow.remainingBalance();
        uint256 freelancerAmount = remaining == 0 ? 0 : seed % (remaining + 1);
        uint256 clientRefund = remaining - freelancerAmount;
        vm.prank(arbiter);
        escrow.resolveDispute(freelancerAmount, clientRefund);
    }

    function warpPastDeadline() external {
        if (block.timestamp < deadline + 1) {
            vm.warp(deadline + 1);
        }
    }

    function refundAfterExpiry() external {
        if (_status() != FreelanceEscrow.Status.Funded) return;
        if (block.timestamp <= deadline) return;
        vm.prank(client);
        escrow.refundAfterExpiry();
    }
}


/// @notice Solvency invariants over the escrow lifecycle.
/// @dev The core property: payouts never exceed locked funds, and the
///      contract's balance plus what it has released always accounts for
///      exactly the funded total once funding has happened.
contract EscrowInvariantTest is Test {
    EscrowHandler public handler;
    FreelanceEscrow public escrow;

    function setUp() public {
        address client = makeAddr("client");
        address freelancer = makeAddr("freelancer");
        address arbiter = makeAddr("arbiter");
        handler = new EscrowHandler(client, freelancer, arbiter);
        escrow = handler.escrow();

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = EscrowHandler.submitMilestone.selector;
        selectors[1] = EscrowHandler.approveMilestone.selector;
        selectors[2] = EscrowHandler.raiseDispute.selector;
        selectors[3] = EscrowHandler.resolveDispute.selector;
        selectors[4] = EscrowHandler.warpPastDeadline.selector;
        selectors[5] = EscrowHandler.refundAfterExpiry.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_released_never_exceeds_total() public view {
        assertLe(escrow.releasedAmount(), escrow.totalAmount());
    }

    function invariant_balance_never_exceeds_total() public view {
        assertLe(address(escrow).balance, escrow.totalAmount());
    }

    function invariant_funded_accounting() public view {
        FreelanceEscrow.Status status = escrow.status();
        if (status == FreelanceEscrow.Status.Created || status == FreelanceEscrow.Status.Cancelled) {
            return;
        }
        // After funding, every wei is either still held or released.
        assertEq(address(escrow).balance + escrow.releasedAmount(), escrow.totalAmount());
    }

    function invariant_terminal_states_drain() public view {
        FreelanceEscrow.Status status = escrow.status();
        if (
            status == FreelanceEscrow.Status.Completed || status == FreelanceEscrow.Status.Resolved
                || status == FreelanceEscrow.Status.Expired
        ) {
            assertEq(address(escrow).balance, 0);
            assertEq(escrow.releasedAmount(), escrow.totalAmount());
        }
    }

    function invariant_approved_sum_matches_released_while_active() public view {
        FreelanceEscrow.Status status = escrow.status();
        if (status != FreelanceEscrow.Status.Funded && status != FreelanceEscrow.Status.Completed) {
            return;
        }
        // While no dispute/expiry ruling has overwritten releasedAmount,
        // released must equal exactly the sum of approved milestones.
        uint256 sum;
        for (uint256 i = 0; i < 3; i++) {
            (,, bool submitted, bool approved) = escrow.milestones(i);
            submitted;
            if (approved) {
                (, uint256 amount,,) = escrow.milestones(i);
                sum += amount;
            }
        }
        assertEq(escrow.releasedAmount(), sum);
        if (status == FreelanceEscrow.Status.Completed) {
            assertEq(sum, escrow.totalAmount());
        }
    }

    function invariant_terms_immutable() public view {
        assertEq(escrow.totalAmount(), 6 ether);
        assertEq(escrow.milestoneCount(), 3);
        (, uint256 a0,,) = escrow.milestones(0);
        (, uint256 a1,,) = escrow.milestones(1);
        (, uint256 a2,,) = escrow.milestones(2);
        assertEq(a0, 1 ether);
        assertEq(a1, 2 ether);
        assertEq(a2, 3 ether);
    }
}

/// @notice Handler creating escrows through the factory.
contract FactoryHandler is Test {
    EscrowFactory public factory;
    address public client;
    address public freelancer;
    uint256 public created;

    constructor(address _client, address _freelancer) {
        client = _client;
        freelancer = _freelancer;
        factory = new EscrowFactory();
    }

    function createEscrow() external {
        address arbiter = makeAddr("arbiter");
        string[] memory descriptions = new string[](2);
        descriptions[0] = "a";
        descriptions[1] = "b";
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
        vm.prank(client);
        factory.createEscrow(freelancer, arbiter, descriptions, amounts, block.timestamp + 7 days);
        created++;
    }
}

/// @notice Factory registry invariants: the on-chain count and the
///         per-user lists must track exactly the escrows created.
contract FactoryInvariantTest is Test {
    FactoryHandler public handler;
    EscrowFactory public factory;
    address public client;
    address public freelancer;

    function setUp() public {
        client = makeAddr("client");
        freelancer = makeAddr("freelancer");
        handler = new FactoryHandler(client, freelancer);
        factory = handler.factory();

        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = FactoryHandler.createEscrow.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_registry_tracks_created() public view {
        assertEq(factory.escrowCount(), handler.created());
        assertEq(factory.escrowsFor(client).length, handler.created());
        assertEq(factory.escrowsFor(freelancer).length, handler.created());
    }

    function invariant_registered_escrows_belong_to_client() public view {
        for (uint256 i = 0; i < factory.escrowCount(); i++) {
            FreelanceEscrow escrow = factory.escrows(i);
            assertEq(escrow.client(), client);
            assertEq(escrow.freelancer(), freelancer);
            assertEq(escrow.totalAmount(), 2 ether);
        }
    }
}
