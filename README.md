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
  --private-key $PRIVATE_KEY

  forge script script/Deploy.s.sol:DeployScript \
  --rpc-url base_sepolia \
  --account <wallet-name> \
  --sender $(cast wallet address --account <wallet-name>) \
  --broadcast \
  --verify \
  -vvvv