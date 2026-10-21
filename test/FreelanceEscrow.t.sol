// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {FreelanceEscrow} from "../src/FreelanceEscrow.sol";
import {EscrowFactory} from "../src/EscrowFactory.sol";

/// @notice Shared fixture: a 3-milestone escrow (1 + 2 + 3 = 6 ether).
contract EscrowFixture is Test {
    FreelanceEscrow escrow;
    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address arbiter = makeAddr("arbiter");

    string[] descriptions;
    uint256[] amounts;
    uint256 deadline;

    function setUp() public virtual {
        descriptions.push("Design mockups");
        descriptions.push("Frontend build");
        descriptions.push("Deployment + docs");
        amounts.push(1 ether);
        amounts.push(2 ether);
        amounts.push(3 ether);
        deadline = block.timestamp + 30 days;

        escrow = new FreelanceEscrow(client, freelancer, arbiter, descriptions, amounts, deadline);
        vm.deal(client, 100 ether);
    }

    function _fund() internal {
        vm.prank(client);
        escrow.fund{value: 6 ether}();
    }
}

contract ConstructorTest is EscrowFixture {
    function test_constructor_sets_terms() public view {
        assertEq(escrow.client(), client);
        assertEq(escrow.freelancer(), freelancer);
        assertEq(escrow.arbiter(), arbiter);
        assertEq(escrow.totalAmount(), 6 ether);
        assertEq(escrow.deadline(), deadline);
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Created));
        assertEq(escrow.milestoneCount(), 3);
    }

    function test_constructor_rejects_zero_address() public {
        vm.expectRevert(FreelanceEscrow.ZeroAddress.selector);
        new FreelanceEscrow(address(0), freelancer, arbiter, descriptions, amounts, deadline);
    }

    function test_constructor_rejects_empty_milestones() public {
        string[] memory empty;
        uint256[] memory emptyAmt;
        vm.expectRevert(FreelanceEscrow.NoMilestones.selector);
        new FreelanceEscrow(client, freelancer, arbiter, empty, emptyAmt, deadline);
    }

    function test_constructor_rejects_mismatched_arrays() public {
        uint256[] memory one = new uint256[](1);
        one[0] = 1 ether;
        vm.expectRevert(FreelanceEscrow.NoMilestones.selector);
        new FreelanceEscrow(client, freelancer, arbiter, descriptions, one, deadline);
    }

    function test_constructor_rejects_zero_milestone_amount() public {
        amounts[1] = 0;
        vm.expectRevert(FreelanceEscrow.MilestoneAmountZero.selector);
        new FreelanceEscrow(client, freelancer, arbiter, descriptions, amounts, deadline);
    }

    function test_constructor_rejects_past_deadline() public {
        vm.expectRevert(FreelanceEscrow.DeadlineNotInFuture.selector);
        new FreelanceEscrow(client, freelancer, arbiter, descriptions, amounts, block.timestamp);
    }
}

contract FundingTest is EscrowFixture {
    function test_fund_locks_exact_total() public {
        vm.expectEmit(true, false, false, true);
        emit FreelanceEscrow.Funded(client, 6 ether);
        vm.prank(client);
        escrow.fund{value: 6 ether}();
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Funded));
        assertEq(address(escrow).balance, 6 ether);
    }

    function test_fund_rejects_wrong_amount() public {
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongFundingAmount.selector, 6 ether, 5 ether
            )
        );
        escrow.fund{value: 5 ether}();
    }

    function test_fund_rejects_non_client() public {
        vm.deal(freelancer, 10 ether);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.fund{value: 6 ether}();
    }

    function test_fund_rejects_double_funding() public {
        _fund();
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongStatus.selector,
                FreelanceEscrow.Status.Created,
                FreelanceEscrow.Status.Funded
            )
        );
        escrow.fund{value: 6 ether}();
    }

    function test_cancel_before_funding() public {
        vm.expectEmit(true, false, false, false);
        emit FreelanceEscrow.Cancelled(client);
        vm.prank(client);
        escrow.cancel();
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Cancelled));
    }

    function test_cancel_rejects_after_funding() public {
        _fund();
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongStatus.selector,
                FreelanceEscrow.Status.Created,
                FreelanceEscrow.Status.Funded
            )
        );
        escrow.cancel();
    }

    function test_cancel_rejects_non_client() public {
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.cancel();
    }
}

contract MilestoneTest is EscrowFixture {
    function test_full_happy_path() public {
        _fund();

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(freelancer);
            escrow.submitMilestone(i);
            vm.prank(client);
            escrow.approveMilestone(i);
        }

        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Completed));
        assertEq(escrow.releasedAmount(), 6 ether);
        assertEq(freelancer.balance, 6 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_submit_rejects_non_freelancer() public {
        _fund();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.NotFreelancer.selector);
        escrow.submitMilestone(0);
    }

    function test_submit_rejects_unfunded() public {
        vm.prank(freelancer);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongStatus.selector,
                FreelanceEscrow.Status.Funded,
                FreelanceEscrow.Status.Created
            )
        );
        escrow.submitMilestone(0);
    }

    function test_submit_rejects_out_of_range() public {
        _fund();
        vm.prank(freelancer);
        vm.expectRevert(
            abi.encodeWithSelector(FreelanceEscrow.MilestoneOutOfRange.selector, 7)
        );
        escrow.submitMilestone(7);
    }

    function test_approve_rejects_unsubmitted() public {
        _fund();
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(FreelanceEscrow.MilestoneNotSubmitted.selector, 0)
        );
        escrow.approveMilestone(0);
    }

    function test_approve_rejects_non_client() public {
        _fund();
        vm.prank(freelancer);
        escrow.submitMilestone(0);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.approveMilestone(0);
    }

    function test_approve_pays_single_milestone() public {
        _fund();
        uint256 before = freelancer.balance;

        vm.prank(freelancer);
        escrow.submitMilestone(1);

        vm.expectEmit(true, true, false, true);
        emit FreelanceEscrow.MilestoneApproved(1, freelancer, 2 ether);

        vm.prank(client);
        escrow.approveMilestone(1);

        assertEq(freelancer.balance - before, 2 ether);
        assertEq(escrow.releasedAmount(), 2 ether);
        assertEq(address(escrow).balance, 4 ether);
        // Not complete yet: milestones 0 and 2 pending.
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Funded));
    }

    function test_approve_rejects_double_approval() public {
        _fund();
        vm.prank(freelancer);
        escrow.submitMilestone(0);
        vm.prank(client);
        escrow.approveMilestone(0);
        // Re-submitting an approved milestone reverts at submit time...
        vm.prank(freelancer);
        vm.expectRevert(
            abi.encodeWithSelector(FreelanceEscrow.MilestoneAlreadyApproved.selector, 0)
        );
        escrow.submitMilestone(0);
        // ...and so does re-approving it.
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(FreelanceEscrow.MilestoneAlreadyApproved.selector, 0)
        );
        escrow.approveMilestone(0);
    }

    function test_out_of_order_approval() public {
        _fund();
        // Milestones need not be approved in order.
        vm.prank(freelancer);
        escrow.submitMilestone(2);
        vm.prank(client);
        escrow.approveMilestone(2);
        assertEq(freelancer.balance, 3 ether);
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Funded));
    }
}

contract DisputeTest is EscrowFixture {
    function test_dispute_full_refund_to_client() public {
        _fund();
        uint256 clientBefore = client.balance;

        vm.prank(freelancer);
        escrow.raiseDispute("scope creep");
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Disputed));

        vm.prank(arbiter);
        escrow.resolveDispute(0, 6 ether);

        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Resolved));
        assertEq(client.balance - clientBefore, 6 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_dispute_split_after_partial_release() public {
        _fund();
        // Client approved milestone 0 (1 ether) before the dispute.
        vm.prank(freelancer);
        escrow.submitMilestone(0);
        vm.prank(client);
        escrow.approveMilestone(0);

        uint256 freelancerBefore = freelancer.balance;
        uint256 clientBefore = client.balance;

        vm.prank(client);
        escrow.raiseDispute("quality issues");
        // Remaining = 5 ether; arbiter awards 2 ether, refunds 3 ether.
        vm.prank(arbiter);
        escrow.resolveDispute(2 ether, 3 ether);

        assertEq(freelancer.balance - freelancerBefore, 2 ether);
        assertEq(client.balance - clientBefore, 3 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_dispute_full_release_to_freelancer() public {
        _fund();
        uint256 before = freelancer.balance;
        vm.prank(freelancer);
        escrow.raiseDispute("client unresponsive");
        vm.prank(arbiter);
        escrow.resolveDispute(6 ether, 0);
        assertEq(freelancer.balance - before, 6 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_dispute_rejects_third_party() public {
        _fund();
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(FreelanceEscrow.NotParty.selector);
        escrow.raiseDispute("nosy");
    }

    function test_dispute_pauses_approvals() public {
        _fund();
        vm.prank(freelancer);
        escrow.submitMilestone(0);
        vm.prank(client);
        escrow.raiseDispute("hold on");
        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongStatus.selector,
                FreelanceEscrow.Status.Funded,
                FreelanceEscrow.Status.Disputed
            )
        );
        escrow.approveMilestone(0);
    }

    function test_resolve_rejects_wrong_split_sum() public {
        _fund();
        vm.prank(client);
        escrow.raiseDispute("x");
        vm.prank(arbiter);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongFundingAmount.selector, 6 ether, 5 ether
            )
        );
        escrow.resolveDispute(2 ether, 3 ether); // sums to 5, not 6
    }

    function test_resolve_rejects_non_arbiter() public {
        _fund();
        vm.prank(client);
        escrow.raiseDispute("x");
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.NotArbiter.selector);
        escrow.resolveDispute(0, 6 ether);
    }

    function test_resolve_rejects_without_dispute() public {
        _fund();
        vm.prank(arbiter);
        vm.expectRevert(
            abi.encodeWithSelector(
                FreelanceEscrow.WrongStatus.selector,
                FreelanceEscrow.Status.Disputed,
                FreelanceEscrow.Status.Funded
            )
        );
        escrow.resolveDispute(0, 6 ether);
    }
}

contract ExpiryTest is EscrowFixture {
    function test_refund_after_expiry() public {
        _fund();
        uint256 clientBefore = client.balance;
        vm.warp(deadline + 1);
        vm.expectEmit(true, false, false, true);
        emit FreelanceEscrow.ExpiredRefunded(client, 6 ether);
        vm.prank(client);
        escrow.refundAfterExpiry();
        assertEq(uint256(escrow.status()), uint256(FreelanceEscrow.Status.Expired));
        assertEq(client.balance - clientBefore, 6 ether);
    }

    function test_refund_after_expiry_partial() public {
        _fund();
        // Milestone 0 already approved (1 ether paid); refund covers the rest.
        vm.prank(freelancer);
        escrow.submitMilestone(0);
        vm.prank(client);
        escrow.approveMilestone(0);

        uint256 clientBefore = client.balance;
        vm.warp(deadline + 1);
        vm.prank(client);
        escrow.refundAfterExpiry();
        assertEq(client.balance - clientBefore, 5 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_refund_rejects_before_deadline() public {
        _fund();
        vm.prank(client);
        vm.expectRevert(FreelanceEscrow.DeadlineNotInFuture.selector);
        escrow.refundAfterExpiry();
    }

    function test_refund_rejects_non_client() public {
        _fund();
        vm.warp(deadline + 1);
        vm.prank(freelancer);
        vm.expectRevert(FreelanceEscrow.NotClient.selector);
        escrow.refundAfterExpiry();
    }
}

contract FactoryTest is Test {
    EscrowFactory factory;
    address client = makeAddr("client");
    address freelancer = makeAddr("freelancer");
    address arbiter = makeAddr("arbiter");

    function setUp() public {
        factory = new EscrowFactory();
    }

    function _terms()
        internal
        pure
        returns (string[] memory descriptions, uint256[] memory amounts)
    {
        descriptions = new string[](2);
        descriptions[0] = "a";
        descriptions[1] = "b";
        amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
    }

    function test_factory_creates_and_registers() public {
        (string[] memory d, uint256[] memory a) = _terms();
        vm.prank(client);
        FreelanceEscrow escrow =
            factory.createEscrow(freelancer, arbiter, d, a, block.timestamp + 7 days);

        assertEq(factory.escrowCount(), 1);
        assertEq(address(factory.escrows(0)), address(escrow));
        assertEq(escrow.client(), client);
        assertEq(escrow.totalAmount(), 2 ether);

        FreelanceEscrow[] memory forClient = factory.escrowsFor(client);
        FreelanceEscrow[] memory forFreelancer = factory.escrowsFor(freelancer);
        assertEq(forClient.length, 1);
        assertEq(forFreelancer.length, 1);
        assertEq(address(forClient[0]), address(escrow));

        // Arbiter is not registered as a party.
        assertEq(factory.escrowsFor(arbiter).length, 0);
    }

    function test_factory_caller_is_client() public {
        (string[] memory d, uint256[] memory a) = _terms();
        vm.prank(client);
        FreelanceEscrow escrow =
            factory.createEscrow(freelancer, arbiter, d, a, block.timestamp + 7 days);
        assertEq(escrow.client(), client);
        assertTrue(escrow.client() != freelancer);
    }

    function test_factory_tracks_multiple_escrows() public {
        (string[] memory d, uint256[] memory a) = _terms();
        vm.startPrank(client);
        factory.createEscrow(freelancer, arbiter, d, a, block.timestamp + 7 days);
        factory.createEscrow(freelancer, arbiter, d, a, block.timestamp + 7 days);
        vm.stopPrank();
        assertEq(factory.escrowCount(), 2);
        assertEq(factory.escrowsFor(client).length, 2);
        assertEq(factory.escrowsFor(freelancer).length, 2);
    }
}
