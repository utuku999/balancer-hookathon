## BALANCER HOOKS

### V3

https://balancer.fi/

Run the commands using Git Bash terminal.

Init:

```shell
$ forge init

$ forge install https://github.com/balancer/balancer-v3-monorepo

$ forge install OpenZeppelin/openzeppelin-contracts

$ forge install https://github.com/balancer/permit2
```

Remappings in remappings.txt file:

- @test/=lib/balancer-v3-monorepo/pkg/

- @balancer-labs/v3-solidity-utils/=lib/balancer-v3-monorepo/pkg/solidity-utils/

- @balancer-labs/v3-pool-utils/=lib/balancer-v3-monorepo/pkg/pool-utils/

- @balancer-labs/v3-interfaces/=lib/balancer-v3-monorepo/pkg/interfaces/

- @balancer-labs/v3-pool-weighted/=lib/balancer-v3-monorepo/pkg/pool-weighted/

- @balancer-labs/v3-vault/=lib/balancer-v3-monorepo/pkg/vault/

- @openzeppelin/=lib/openzeppelin-contracts/

- permit2/=lib/permit2/

https://book.getfoundry.sh/

https://github.com/balancer/balancer-v3-monorepo

https://www.openzeppelin.com/solidity-contracts

Useful commands:

```shell
$ forge compile

$ forge build

$ forge test
```

Force compiler:

```shell
$ forge compile --evm-version cancun --force

$ forge build --evm-version cancun --force

$ forge test --evm-version cancun --force
```

```shell

$ forge create --rpc-url <your_rpc_url> --private-key <your_private_key> src/MyContract.sol:MyContract

$ forge verify-contract \
    --chain-id 11155111 \
    --num-of-optimizations 1000000 \
    --watch \
    --constructor-args $(cast abi-encode "constructor(string,string,uint256,uint256)" "ForgeUSD" "FUSD" 18 1000000000000000000000) \
    --etherscan-api-key <your_etherscan_api_key> \
    --compiler-version v0.8.10+commit.fc410830 \
    <the_contract_address> \
    src/MyToken.sol:MyToken
```

Docs: https://docs-v3.balancer.fi/concepts/core-concepts/hooks.html

![Hooks](./img/hooks.png?raw=true "Hooks")

![Flags](./img/flags.png?raw=true "Flags")

![Route](./img/route.png?raw=true "Route")

- HOOKS: https://github.com/balancer/scaffold-balancer-v3/tree/main/packages/foundry/contracts/hooks

- TESTS: https://github.com/balancer/scaffold-balancer-v3/tree/main/packages/foundry/test

- Examples: https://hooks.balancer.fi/

- Scaffold: https://github.com/balancer/scaffold-balancer-v3
