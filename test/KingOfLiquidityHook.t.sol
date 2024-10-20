// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {BaseVaultTest} from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import {PoolMock} from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";
import {HooksConfig, LiquidityManagement, PoolRoleAccounts, TokenConfig} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IVaultAdmin} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import {IVaultErrors} from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import {PoolFactoryMock} from "@balancer-labs/v3-vault/contracts/test/PoolFactoryMock.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {ArrayHelpers} from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import {CastingHelpers} from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import {KingOfLiquidityHook} from "../src/KingOfLiquidityHook.sol";

contract KingOfLiquidityHookTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    address payable internal trustedRouter;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

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

    function testRegistryWithWrongFactory() public {
        address testPool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        uint32 pauseWindowEndTime = IVaultAdmin(address(vault))
            .getPauseWindowEndTime();
        uint32 bufferPeriodDuration = IVaultAdmin(address(vault))
            .getBufferPeriodDuration();
        uint32 pauseWindowDuration = pauseWindowEndTime - bufferPeriodDuration;
        address unauthorizedFactory = address(
            new PoolFactoryMock(IVault(address(vault)), pauseWindowDuration)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                testPool,
                unauthorizedFactory
            )
        );
        _registerPoolWithHook(testPool, tokenConfig, unauthorizedFactory);
    }

    function testCreationWithWrongFactory() public {
        address testPool = _createPoolToRegister();
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultErrors.HookRegistrationFailed.selector,
                poolHooksContract,
                testPool,
                address(factoryMock)
            )
        );
        _registerPoolWithHook(testPool, tokenConfig, address(factoryMock));
    }

    function testSuccessfulRegistry() public {
        // Register with the allowed factory.
        address testPool = factoryMock.createPool("Test Pool", "TEST");
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(
            [address(dai), address(usdc)].toMemoryArray().asIERC20()
        );

        _registerPoolWithHook(testPool, tokenConfig, address(factoryMock));

        HooksConfig memory hooksConfig = vault.getHooksConfig(testPool);

        assertEq(
            hooksConfig.hooksContract,
            poolHooksContract,
            "Wrong poolHooksContract"
        );
        assertEq(
            hooksConfig.shouldCallAfterAddLiquidity,
            true,
            "shouldCallAfterAddLiquidity is false"
        );
        assertEq(
            hooksConfig.shouldCallAfterRemoveLiquidity,
            true,
            "shouldCallAfterRemoveLiquidity is false"
        );
        assertEq(
            hooksConfig.shouldCallAfterSwap,
            true,
            "shouldCallAfterSwap is false"
        );
    }

    // Registry tests require a new pool, because an existing pool may be already registered
    function _createPoolToRegister() private returns (address newPool) {
        newPool = address(
            new PoolMock(IVault(address(vault)), "Test Pool", "TestPool")
        );
        vm.label(newPool, "Test Pool");
    }

    function _registerPoolWithHook(
        address testPool,
        TokenConfig[] memory tokenConfig,
        address factory
    ) private {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement;

        PoolFactoryMock(factory).registerPool(
            testPool,
            tokenConfig,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }
}
