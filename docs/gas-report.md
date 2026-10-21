# Gas report

Generated with `forge snapshot` (solc 0.8.24, optimizer enabled, 200 runs).
The full per-test snapshot lives in `.gas-snapshot` and is the regression
baseline — run `forge snapshot --diff` after any contract change to see
what moved.

## How to read these numbers

The figures below are **whole-test gas** from the snapshot: each includes
its fixture (deploying the escrow, funding it) plus the scenario itself.
They are good for tracking regressions between commits, not for quoting
an isolated function cost — e.g. the factory rows include deploying the
factory and the escrow in the test setup.

## Representative scenarios

| Scenario | Gas |
| --- | --- |
| Full happy path: fund, submit + approve 3 milestones | 229,329 |
| Approve a single milestone (submit + approve) | 146,733 |
| Fund the escrow (exact total) | 44,347 |
| Dispute: full refund to client | 109,635 |
| Dispute: split after partial release (1 milestone paid, then split) | 187,617 |
| Dispute: full release to freelancer | 134,809 |
| Refund after expiry (nothing approved) | 81,861 |
| Refund after expiry (1 milestone already paid) | 153,794 |
| Factory: create + register one escrow | 1,365,287 |
| Factory: create + register two escrows | 2,632,651 |

The factory rows are dominated by contract creation: deploying a
`FreelanceEscrow` costs roughly 1.3M gas, so creating escrows in bulk
through the factory is the expensive path in this system. Milestone
approvals, disputes, and refunds are all under 200k gas per scenario.

## Invariant coverage behind the numbers

8 invariant tests, each run 256 times with a call depth of 100
(25,600 handler calls per invariant, 0 reverts):

- `releasedAmount <= totalAmount` always
- contract balance `<= totalAmount` always
- after funding, `balance + releasedAmount == totalAmount`
- terminal states (Completed / Resolved / Expired) drain to balance 0
  with `releasedAmount == totalAmount`
- while Funded / Completed, `releasedAmount` equals exactly the sum of
  approved milestone amounts
- milestone amounts and total are immutable (1 + 2 + 3 = 6 ether fixture)
- factory registry count and per-user lists track created escrows exactly
