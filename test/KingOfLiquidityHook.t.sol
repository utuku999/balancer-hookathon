// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {BaseVaultTest} from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import {PoolMock} from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import {PoolFactoryMock} from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import {KingOfLiquidityHook} from "../src/KingOfLiquidityHook.sol";

contract KingOfLiquidityHookTest is BaseVaultTest {
    address payable internal trustedRouter;

    function createHook() internal override returns (address) {
        trustedRouter = payable(router);

        vm.prank(lp);
        uint64 fee = 10;
        address customHook = address(
            new KingOfLiquidityHook(
                IVault(address(vault)),
                address(factoryMock),
                trustedRouter,
                fee
            )
        );
        vm.label(customHook, "Custom Hook");
        return customHook;
    }
}
