## PayFrom Contracts

### PayfromDelegate (sponsored transactions via EIP-7702)

Minimal EIP-7702 delegate contract. A PayFrom-managed wallet (EOA) delegates
its code to this contract, after which anyone (in practice the sponsor
wallet, which pays the gas) can call `executeOps(calls, deadline, signature)`
to run a batch of calls from the wallet, such as an ERC-20 transfer or an
approve plus a swap or bridge deposit, without the wallet holding native gas.

Authorization comes only from the wallet's own signature, never from the
caller. The signed digest is

```
keccak256(abi.encode(address(this), block.chainid, calls, nonce, deadline))
```

so a signature is bound to one wallet, one chain, the exact calls, a single
use (`nonce` increments before any call runs) and a deadline. Calls to the
wallet itself or the zero address are rejected, and a failing call reverts
the whole batch.

The contract has no constructor arguments or roles, so the same bytecode is
deployed once per chain.

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Adding a deployer key

Never put a private key in `.env`; import it into an encrypted keystore instead:

```shell
$ cast wallet import <account_name> --interactive
```

### Deploy

```shell
$ forge script script/DeployPayfromDelegate.s.sol:DeployPayfromDelegate \
  --rpc-url <rpc_endpoints> \
  --account <account_name> \
  --sender $(cast wallet address --account <account_name>) \
  --broadcast \
  --verify \
  -vvvv
```
