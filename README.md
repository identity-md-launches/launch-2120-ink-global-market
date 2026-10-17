# Ink Global Market (INK)

`src/InkToken.sol:InkToken` is a fixed-supply ERC-20. Its constructor mints all
1,000,000,000 INK to its immediate deployer (`msg.sender`). It inherits the
unmodified OpenZeppelin Contracts v5.4.0 ERC-20 implementation.

## Token and deployment parameters

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `InkToken` |
| Name | `Ink Global Market` |
| Symbol | `INK` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment value | `0` ETH |
| Initial recipient | Immediate deploying account or factory |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun (supported by the specified Ethereum launch chain) |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

There is one production contract and no application contracts, initializer,
proxy, linked library, or external contract dependency at deployment. The
constructor makes no external calls. Deploy the compiled creation bytecode for
`InkToken` without appending constructor arguments. A factory receives the entire
supply when it creates the token; the transaction's origin does not receive it.

## Behavior and assumptions

The requested token is interpreted as a standard, unrestricted ERC-20: transfers
deliver exactly their stated amount, with no token transfer fee, tax, burn,
rebasing, vesting, or holder restrictions. The supply never changes after
construction. There is no owner, role manager, mint function, burn function,
pause, blacklist, seizure, or upgrade authority.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
ERC-6093 custom errors on invalid operations. Transfers to the zero address and
approvals to a zero spender revert. Zero-value transfers between nonzero
addresses and self-transfers are supported. An empty account can approve a
spender. `approve` replaces the existing allowance; setting it to zero revokes it.
Finite allowances decrease on spending; the maximum `uint256` allowance is
treated as unlimited and does not decrease. Even a holder calling `transferFrom`
on its own balance needs an allowance; it can use `transfer` directly instead.

Minting and transfers emit `Transfer`; explicit approvals emit `Approval`.
OpenZeppelin v5 does not emit `Approval` when `transferFrom` spends an allowance.
Integrations should query `allowance` for its current value. Transfers invoke no
recipient callbacks, and the token has no external calls during normal use.

## Build and test

From this repository's root, with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xef7e9b50baec01965dc70bfbb9115da149cfcb36b1912789529286ece452470f forge test
forge fmt --check
```

All Solidity dependencies are ordinary files in `vendor/openzeppelin`; see its
`PROVENANCE.md` for the pinned upstream commit and checksums and `LICENSE` for
the MIT terms. No package install, RPC, fork, wallet, environment-based test
configuration, FFI, or filesystem cheatcode is needed. Tests include a small
local Foundry cheatcode interface instead of a forge-std dependency. The test
fixtures' addresses have no deployment role.

The suite covers metadata, exact constructor allocation and mint events,
factory deployment, transfer/approval events, full-balance and zero transfers,
self-transfers, finite/unlimited allowances, revocation, unauthorized spending,
invalid addresses, insufficient balances, rollback of failed spending, rejection
of administrative selectors, and runtime opcode restrictions. Five fuzz tests
run 1,000 cases each. A stateful invariant runs 128 sequences of 64 calls,
comparing balances and allowances against an independent model and checking
that total supply and aggregate balances remain constant.

The distribution test models exact transfers through contract holders. It does
not implement or test a Uniswap v4 pool. The supplied protected launch suite
depends on the separate launch harness, manifest-derived environment, and pool
contracts that are not part of this token repository; the launch verifier runs
that integration separately.

## After launch

No token settings, owner actions, keepers, or external services need configuring.
The launch operator is responsible for creating the token through the intended
factory, verifying its deployed source and metadata, confirming the entire
initial supply reached the factory, and executing the launch distributions.
The constructor intentionally performs no allocations to other recipients.

For this assignment, the separate launch system handles the specified Ethereum
launch: 10% to its swarm distributor, 80% to liquidity, and the remaining 10% to
the requester's specified recipient. The paired asset, opening market cap,
pool fee, and pool configuration belong to that system; no pool settings or
recipient addresses are embedded in this token. The builder does not generate
`launch.json` or broadcast a deployment.

Holders must safeguard their wallets and approve only trusted spenders. Prefer
exact allowances; when changing an existing nonzero allowance, first revoke it
and wait for confirmation to reduce the standard ERC-20 approval ordering risk.
There is no administrator who can reverse transfers, recover lost keys, or
rescue assets sent to the token contract. Plain ETH transfers are rejected;
forced ETH or accidentally sent tokens cannot be rescued.

The security review for this implementation checks the constructor-only mint,
allowance authorization, checked balance arithmetic, zero-address validation,
absence of external calls, and absence of privileged or upgradeable behavior.
Foundry unit, fuzz, and invariant tests are the automated checks supplied here.
Slither and Mythril were not run. These checks do not replace the independent
security review required before release.
