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


### Deploy

```shell
$ forge script script/Deploy.s.sol:DeployScript \
    --rpc-url <rpc_endpoints> \
    --broadcast \
    --verify \
    -vvvv
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

### To add a supported token
```shell
$ cast send <ROUTER_ADDRESS> \
  "addSupportedToken(address)" \
  <TOKEN_ADDRESS> \
  --rpc-url <rpc_endpoints> \
  --private-key $PRIVATE_KEY
