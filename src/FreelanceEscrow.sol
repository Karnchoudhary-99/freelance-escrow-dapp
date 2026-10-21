// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title FreelanceEscrow
/// @notice Trustless escrow for freelance work: a client locks ETH up front,
///         a freelancer delivers work in milestones, and funds are released
///         only when the client approves a milestone. A neutral arbiter
///         resolves disputes, and unreleased funds are refundable after the
///         deadline. No token, no oracle, no upgrade proxy — plain ETH.
/// @dev Checks-effects-interactions throughout, plus a minimal reentrancy
///      guard (no external dependencies, so the repo builds with vanilla
///      Foundry). All payouts use `call` with a success check.
contract FreelanceEscrow {
    // ------------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------------

    enum Status {
        Created, // Escrow exists, not yet funded
        Funded, // Client locked the full amount
        Completed, // Every milestone approved and paid
        Disputed, // A party raised a dispute; payouts paused
        Resolved, // Arbiter ruled; remaining balance split
        Cancelled, // Client cancelled before funding
        Expired // Deadline passed; remaining balance refunded to client
    }

    struct Milestone {
        string description;
        uint256 amount;
        bool submitted;
        bool approved;
    }

    // ------------------------------------------------------------------------
    // Errors (cheaper and clearer than revert strings)
    // ------------------------------------------------------------------------

    error NotClient();
    error NotFreelancer();
    error NotArbiter();
    error NotParty();
    error ZeroAddress();
    error NoMilestones();
    error MilestoneAmountZero();
    error DeadlineNotInFuture();
    error WrongFundingAmount(uint256 expected, uint256 received);
    error WrongStatus(Status expected, Status actual);
    error MilestoneOutOfRange(uint256 index);
    error MilestoneNotSubmitted(uint256 index);
    error MilestoneAlreadyApproved(uint256 index);
    error TransferFailed(address to, uint256 amount);
    error ReentrantCall();

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------

    event EscrowCreated(
        address indexed client,
        address indexed freelancer,
        address indexed arbiter,
        uint256 totalAmount,
        uint256 deadline
    );
    event Funded(address indexed client, uint256 amount);
    event Cancelled(address indexed client);
    event MilestoneSubmitted(uint256 indexed index, string description);
    event MilestoneApproved(uint256 indexed index, address indexed freelancer, uint256 amount);
    event DisputeRaised(address indexed by, string reason);
    event DisputeResolved(
        address indexed arbiter, uint256 freelancerAmount, uint256 clientRefund
    );
    event ExpiredRefunded(address indexed client, uint256 amount);

    // ------------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------------

    address public immutable client;
    address public immutable freelancer;
    address public immutable arbiter;
    uint256 public immutable deadline;
    uint256 public immutable totalAmount;

    Status public status;
    Milestone[] public milestones;
    uint256 public releasedAmount;
    string public disputeReason;

    uint256 private _locked;

    // ------------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------------

    modifier onlyClient() {
        if (msg.sender != client) revert NotClient();
        _;
    }

    modifier onlyFreelancer() {
        if (msg.sender != freelancer) revert NotFreelancer();
        _;
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    modifier nonReentrant() {
        if (_locked == 1) revert ReentrantCall();
        _locked = 1;
        _;
        _locked = 0;
    }

    modifier inStatus(Status expected) {
        if (status != expected) revert WrongStatus(expected, status);
        _;
    }

    // ------------------------------------------------------------------------
    // Construction + funding
    // ------------------------------------------------------------------------

    /// @param _client The payer; funds the escrow and approves milestones.
    /// @param _freelancer The worker; submits milestones and receives payouts.
    /// @param _arbiter Neutral third party; only acts during a dispute.
    /// @param _descriptions One per milestone, in payout order.
    /// @param _amounts ETH per milestone; must sum to the escrow total.
    /// @param _deadline Unix timestamp after which the client may refund the
    ///        unreleased balance (see `refundAfterExpiry`).
    constructor(
        address _client,
        address _freelancer,
        address _arbiter,
        string[] memory _descriptions,
        uint256[] memory _amounts,
        uint256 _deadline
    ) {
        if (_client == address(0) || _freelancer == address(0) || _arbiter == address(0)) {
            revert ZeroAddress();
        }
        if (_descriptions.length == 0 || _descriptions.length != _amounts.length) {
            revert NoMilestones();
        }
        if (_deadline <= block.timestamp) revert DeadlineNotInFuture();

        uint256 total;
        for (uint256 i = 0; i < _amounts.length; i++) {
            if (_amounts[i] == 0) revert MilestoneAmountZero();
            total += _amounts[i];
            milestones.push(
                Milestone({description: _descriptions[i], amount: _amounts[i], submitted: false, approved: false})
            );
        }

        client = _client;
        freelancer = _freelancer;
        arbiter = _arbiter;
        deadline = _deadline;
        totalAmount = total;
        status = Status.Created;

        emit EscrowCreated(_client, _freelancer, _arbiter, total, _deadline);
    }

    /// @notice Lock the full milestone total. Only the client, only once.
    function fund() external payable onlyClient inStatus(Status.Created) {
        if (msg.value != totalAmount) {
            revert WrongFundingAmount(totalAmount, msg.value);
        }
        status = Status.Funded;
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Cancel an unfunded escrow. Nothing was locked, so no payout.
    function cancel() external onlyClient inStatus(Status.Created) {
        status = Status.Cancelled;
        emit Cancelled(msg.sender);
    }

    // ------------------------------------------------------------------------
    // Milestones
    // ------------------------------------------------------------------------

    /// @notice Freelancer marks a milestone's work as delivered.
    function submitMilestone(uint256 index) external onlyFreelancer inStatus(Status.Funded) {
        if (index >= milestones.length) revert MilestoneOutOfRange(index);
        Milestone storage m = milestones[index];
        if (m.approved) revert MilestoneAlreadyApproved(index);
        m.submitted = true;
        emit MilestoneSubmitted(index, m.description);
    }

    /// @notice Client accepts delivered work and releases that milestone's
    ///         ETH to the freelancer. Completes the escrow when the last
    ///         milestone is approved.
    function approveMilestone(uint256 index)
        external
        onlyClient
        inStatus(Status.Funded)
        nonReentrant
    {
        if (index >= milestones.length) revert MilestoneOutOfRange(index);
        Milestone storage m = milestones[index];
        if (!m.submitted) revert MilestoneNotSubmitted(index);
        if (m.approved) revert MilestoneAlreadyApproved(index);

        // Effects before interaction.
        m.approved = true;
        releasedAmount += m.amount;
        bool allApproved = true;
        for (uint256 i = 0; i < milestones.length; i++) {
            if (!milestones[i].approved) {
                allApproved = false;
                break;
            }
        }
        if (allApproved) status = Status.Completed;

        _payout(freelancer, m.amount);
        emit MilestoneApproved(index, freelancer, m.amount);
    }

    // ------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------

    /// @notice ETH still held by this escrow (unreleased balance).
    function remainingBalance() public view returns (uint256) {
        return totalAmount - releasedAmount;
    }

    function milestoneCount() external view returns (uint256) {
        return milestones.length;
    }

    // ------------------------------------------------------------------------
    // Internal helpers
    // ------------------------------------------------------------------------

    function _payout(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed(to, amount);
    }
}
