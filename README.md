## PayFrom Contracts

PayFromRouter is a smart contract that spilt funds between merchant account(99%) and PayFrom(1%).

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

### Adding Private Key
NEVER ADD PRIVATE KEY TO .env file; DO THIS INSTEAD
```shell
$ cast wallet import <account_name> --interactive
```

###  Deploy (will prompt for password - SECURE!)

```shell
$ forge script script/Deploy.s.sol:DeployScript \
  --rpc-url <rpc_endpoints> \
  --account <account_name> \
  --sender $(cast wallet address --account <account_name>) \
  --broadcast \
  --verify \
  -vvvv
```

### To add a supported token
```shell
$ cast send <ROUTER_ADDRESS> \
  "addSupportedToken(address)" \
  <TOKEN_ADDRESS> \
  --rpc-url <rpc_endpoints> \
  --private-key $PRIVATE_KEY # only in test, never enter private keys directly use `cast` instead
```

## PayfromDelegate (gasless transfers via EIP-7702)

Minimal EIP-7702 delegate contract: a user's EOA signs a one-time authorization
pointing at this contract's code, after which the backend's sponsor wallet can
call `executeTransfer` to move that EOA's own token balance (no `approve()`
needed) while paying the gas itself. `relayer` is `immutable` - EIP-7702
delegated accounts run this code against their own blank storage, not this
contract's, so anything the relayer-gating depends on has to be baked into the
bytecode rather than set via a mutable storage variable. Deploy one instance
per chain per environment (test/live have separate sponsor wallets, so
separate deployments).

Set `SPONSOR_WALLET_ADDRESS` in `.env` to the sponsor wallet address for the
target environment before deploying.

```shell
$ forge script script/DeployPayfromDelegate.s.sol:DeployPayfromDelegate \
  --rpc-url <rpc_endpoints> \
  --account <account_name> \
  --sender $(cast wallet address --account <account_name>) \
  --broadcast \
  --verify \
  -vvvv
```