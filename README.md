# Freelance Escrow dApp

Trustless freelance escrow on Ethereum: a client locks ETH into a smart
contract, a freelancer delivers work in milestones, funds release only when
the client approves each milestone, a neutral arbiter resolves disputes, and
unreleased funds are refundable after the deadline. Built with Solidity 0.8.24
+ Foundry. No tokens, no oracles, no dependencies.

## How it works

```
Client creates escrow via EscrowFactory (locks nothing yet)
  → Client funds the escrow (exact milestone total)
  → Freelancer submits a milestone
  → Client approves → that milestone's ETH pays out immediately
  → Disagreement? Either party raises a dispute; arbiter splits/refunds/releases
  → Deadline passes? Client refunds whatever was never approved
```

## Quick start

```bash
forge build
forge test                 # 37 tests
# Local demo on Anvil
anvil &
forge script script/Deploy.s.sol --broadcast --rpc-url http://127.0.0.1:8545
```

### Demo walkthrough (Anvil)

```bash
# 1. Deploy the factory (prints its address, e.g. 0x5FbD...)
forge script script/Deploy.s.sol --broadcast --rpc-url http://127.0.0.1:8545

# 2. Create an escrow (client = your Anvil account 0)
cast send <FACTORY> "createEscrow(address,address,string[],uint256[],uint256)" \
  <FREELANCER> <ARBITER> '["Design","Build"]' '[1000000000000000000,2000000000000000000]' \
  <DEADLINE_UNIX> --rpc-url http://127.0.0.1:8545 --private-key <CLIENT_KEY>

# 3. Fund it with the exact total (3 ETH here)
cast send <ESCROW> "fund()" --value 3ether \
  --rpc-url http://127.0.0.1:8545 --private-key <CLIENT_KEY>

# 4. Freelancer submits, client approves -> 1 ETH pays out
cast send <ESCROW> "submitMilestone(uint256)" 0 \
  --rpc-url http://127.0.0.1:8545 --private-key <FREELANCER_KEY>
cast send <ESCROW> "approveMilestone(uint256)" 0 \
  --rpc-url http://127.0.0.1:8545 --private-key <CLIENT_KEY>
```

## Contracts

| Contract | Role |
|---|---|
| `src/FreelanceEscrow.sol` | One escrow: milestones, funding, approvals, disputes, expiry refund |
| `src/EscrowFactory.sol` | Deploys escrows, keeps a registry + per-user lookup |

Key `FreelanceEscrow` entry points:

| Function | Who | What |
|---|---|---|
| `fund()` (payable) | client | Locks the exact milestone total |
| `cancel()` | client | Cancels an unfunded escrow |
| `submitMilestone(i)` | freelancer | Marks milestone `i` delivered |
| `approveMilestone(i)` | client | Pays milestone `i` to the freelancer; completes at the last one |
| `raiseDispute(reason)` | client / freelancer | Freezes payouts |
| `resolveDispute(toFreelancer, toClient)` | arbiter | Splits remaining balance; the two amounts must sum exactly |
| `refundAfterExpiry()` | client | After the deadline, reclaims the unreleased balance |

Lifecycle: `Created → Funded → Completed`, with side branches
`Created → Cancelled`, `Funded → Disputed → Resolved`, and
`Funded → Expired`.

## Security notes

- Checks-effects-interactions on every payout, plus a minimal
  `nonReentrant` guard (no external deps).
- Payouts use low-level `call` with a success check — no `transfer` gas
  griefing.
- Custom errors everywhere instead of revert strings.
- Arbiter rulings are fully transparent: both split amounts are validated
  on-chain to sum to the remaining balance.

## Tests

```bash
forge test -vv
```

45 tests: constructor validation, funding/cancel, milestone happy path and
access control, dispute rulings (release / refund / split), expiry refunds,
and factory registry — plus 8 invariant (fuzz) tests over the escrow
lifecycle and the factory registry. Run in CI on every push.

### Invariant tests

`test/Invariant.t.sol` drives a funded escrow through random
submit/approve/dispute/resolve/warp/refund sequences (256 runs, depth 100,
0 reverts) and checks the solvency properties: payouts never exceed locked
funds, `balance + released == total` after funding, terminal states drain
fully, and the factory registry tracks created escrows exactly.
See `docs/gas-report.md` for the gas snapshot and the invariant list.

## Roadmap

- [x] Project scaffold (Foundry layout, README, CI)
- [x] `FreelanceEscrow.sol`: create/fund escrow, milestone submission + approval, release
- [x] Dispute flow: raise dispute, arbiter ruling (release / refund / split)
- [x] Deadline + auto-refund on expiry, reentrancy guards, events
- [x] Foundry test suite: happy path, disputes, edge cases, factory (37 tests)
- [x] Deploy script + local Anvil demo walkthrough
- [x] Gas report + invariant tests (fuzz: payouts never exceed locked funds)
- [ ] Self-review, then public

## License

MIT
