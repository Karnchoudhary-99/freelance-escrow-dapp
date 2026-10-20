# Freelance Escrow dApp

Trustless freelance escrow on Ethereum: clients lock payment into a smart
contract, funds release on milestone approval, and a neutral arbiter resolves
disputes. Built with Solidity + Foundry.

## How it works

```
Client creates escrow (locks ETH) → Freelancer submits milestones
  → Client approves milestone → funds released
  → Disagreement? Arbiter splits / refunds / releases
```

## Quick start

```bash
# Install Foundry: https://book.getfoundry.sh/getting-started/installation
forge install
forge build
forge test
# Local demo
anvil & forge script script/Deploy.s.sol --broadcast --rpc-url http://127.0.0.1:8545
```

## Roadmap

- [x] Project scaffold (Foundry layout, README, CI)
- [ ] `FreelanceEscrow.sol`: create/fund escrow, milestone submission + approval, release
- [ ] Dispute flow: raise dispute, arbiter ruling (release / refund / split)
- [ ] Deadline + auto-refund on expiry, reentrancy guards, events
- [ ] Foundry test suite: happy path, disputes, edge cases, invariant tests
- [ ] Deploy script + local Anvil demo walkthrough
- [ ] Self-review, then public

## License

MIT
