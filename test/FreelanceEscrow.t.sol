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
