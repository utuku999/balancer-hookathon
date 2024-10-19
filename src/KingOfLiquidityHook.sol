// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHooks} from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import {IVault} from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {TokenConfig, LiquidityManagement, HookFlags, AddLiquidityKind, RemoveLiquidityKind, AfterSwapParams, SwapKind} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import {IBasePoolFactory} from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import {VaultGuard} from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import {IRouterCommon} from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableMap} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import {FixedPoint} from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title King Of Liquidity Hook
 * @notice Tracks and rewards top liquidity providers periodically
 */
contract KingOfLiquidityHook is BaseHooks, VaultGuard, Ownable {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;

    address private immutable _allowedFactory;
    address private immutable _trustedRouter;

    struct LiquidityProvider {
        uint256 totalLiquidity;
        uint256 lastUpdateTime;
        uint256 timeWeightedLiquidity;
    }

    mapping(address user => LiquidityProvider) public liquidityProviders;
    address[] public providerAddresses;

    uint64 public swapFeePercentage;

    uint256 public DISTRIBUTION_PERIOD = 7 days; // Example: 7 days = 604800 seconds.
    uint256 public constant TOP_CONTRIBUTORS_COUNT = 3; // Example: Reward top 3 contributors.
    uint256 public lastDistributionTime;
    uint256 public epochs;

    // Map of tokens with accrued fees.
    EnumerableMap.IERC20ToUint256Map private _tokensWithAccruedFees;

    event FeesCollected(address indexed swapper, IERC20 token, uint256 fee);
    event RewardsDistributed(
        address indexed winner,
        IERC20 token,
        uint256 amount
    );
    event LiquidityAdded(address indexed provider, uint256 amount);
    event LiquidityRemoved(address indexed provider, uint256 amount);

    constructor(
        IVault vault,
        address allowedFactory,
        address trustedRouter,
        uint64 newSwapFeePercentage,
        uint256 newDistributionPeriod
    ) VaultGuard(vault) Ownable(msg.sender) {
        _allowedFactory = allowedFactory;
        _trustedRouter = trustedRouter;
        swapFeePercentage = newSwapFeePercentage;
        DISTRIBUTION_PERIOD = newDistributionPeriod;
        lastDistributionTime = block.timestamp; // Start counting from now on
    }

    // Return true to allow pool registration or false to revert
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public view override returns (bool) {
        // Only pools deployed by an allowed factory may use this hook
        return
            factory == _allowedFactory &&
            IBasePoolFactory(factory).isPoolFromFactory(pool);
    }

    // Return HookFlags struct that indicates which hooks this contract supports
    function getHookFlags()
        public
        pure
        override
        returns (HookFlags memory hookFlags)
    {
        hookFlags.shouldCallAfterAddLiquidity = true; // Calculate user points
        hookFlags.shouldCallAfterRemoveLiquidity = true; // Calculate user points
        hookFlags.shouldCallAfterSwap = true; // Collect fees for rewards
    }

    // Balancer hook function
    function onAfterAddLiquidity(
        address router,
        address /*_pool*/,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory,
        bytes memory
    )
        public
        override
        returns (bool success, uint256[] memory hookAdjustedAmountsInRaw)
    {
        // If the router is not trusted, do not count user contribution
        if (router != _trustedRouter) {
            return (true, amountsInRaw);
        }

        _updateLiquidityProvider(router, bptAmountOut, true);
        _tryRewardAndStartNewEpoch();
        return (true, amountsInRaw);
    }

    // Balancer hook function
    function onAfterRemoveLiquidity(
        address router,
        address /*_pool*/,
        RemoveLiquidityKind,
        uint256 bptAmountIn,
        uint256[] memory,
        uint256[] memory,
        uint256[] memory,
        bytes memory /*userData*/
    )
        public
        override
        returns (bool success, uint256[] memory hookAdjustedAmountsOutRaw)
    {
        // If the router is not trusted, do not count user contribution
        if (router != _trustedRouter) {
            return (true, hookAdjustedAmountsOutRaw);
        }

        _tryRewardAndStartNewEpoch();
        _updateLiquidityProvider(router, bptAmountIn, false);
        return (true, hookAdjustedAmountsOutRaw);
    }

    // Balancer hook function
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyVault returns (bool, uint256) {
        // If the router is not trusted or swap fee not configured, do not use custom logic
        if (params.router != _trustedRouter || swapFeePercentage <= 0) {
            return (true, params.amountCalculatedRaw);
        }

        _tryRewardAndStartNewEpoch();

        uint256 hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        uint256 fee = hookAdjustedAmountCalculatedRaw.mulDown(
            swapFeePercentage
        );

        if (params.kind == SwapKind.EXACT_IN) {
            // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be taken
            // from `amountCalculated`, so we decrease the amount of tokens the Vault will send to the caller.
            //
            // The preceding swap operation has already credited the original `amountCalculated`. Since we're
            // returning `amountCalculated - feeToPay` here, it will only register debt for that reduced amount
            // on settlement. This call to `sendTo` pulls `feeToPay` tokens of `tokenOut` from the Vault to this
            // contract, and registers the additional debt, so that the total debits match the credits and
            // settlement succeeds.
            bool paidTheFee = _collectSwapFee(
                params.router,
                params.tokenOut,
                fee
            );
            if (paidTheFee) {
                hookAdjustedAmountCalculatedRaw -= fee;
            }
        } else {
            // For EXACT_OUT swaps, the `amountCalculated` is the amount of `tokenIn`. The fee must be taken
            // from `amountCalculated`, so we increase the amount of tokens the Vault will ask from the user.
            //
            // The preceding swap operation has already registered debt for the original `amountCalculated`.
            // Since we're returning `amountCalculated + feeToPay` here, it will supply credit for that increased
            // amount on settlement. This call to `sendTo` pulls `feeToPay` tokens of `tokenIn` from the Vault to
            // this contract, and registers the additional debt, so that the total debits match the credits and
            // settlement succeeds.
            bool paidTheFee = _collectSwapFee(
                params.router,
                params.tokenIn,
                fee
            );
            if (paidTheFee) {
                hookAdjustedAmountCalculatedRaw += fee;
            }
        }

        return (true, hookAdjustedAmountCalculatedRaw);
    }

    function _collectSwapFee(
        address router,
        IERC20 token,
        uint256 fee
    ) private returns (bool) {
        if (fee > 0) {
            // Collect fees from the vault, the user will pay them when the Router settles the swap
            _vault.sendTo(token, address(this), fee);
            emit FeesCollected(IRouterCommon(router).getSender(), token, fee);
            return true;
        }
        return false;
    }

    function _updateLiquidityProvider(
        address router,
        uint256 amount,
        bool isAdding
    ) internal {
        address provider = IRouterCommon(router).getSender();
        LiquidityProvider storage lp = liquidityProviders[provider];

        if (lp.totalLiquidity == 0 && isAdding) {
            providerAddresses.push(provider);
            lp.lastUpdateTime = block.timestamp;
        }

        _updateTimeWeightedLiquidity(lp);

        if (isAdding) {
            lp.totalLiquidity += amount;
            emit LiquidityAdded(provider, amount);
        } else {
            lp.totalLiquidity = lp.totalLiquidity > amount
                ? lp.totalLiquidity - amount
                : 0;
            emit LiquidityRemoved(provider, amount);
        }
    }

    function _updateTimeWeightedLiquidity(
        LiquidityProvider storage lp
    ) internal {
        uint256 timePassed = block.timestamp - lp.lastUpdateTime;
        lp.timeWeightedLiquidity += lp.totalLiquidity * timePassed;
        lp.lastUpdateTime = block.timestamp;
    }

    function _epochHasEnded() internal view returns (bool) {
        return block.timestamp >= lastDistributionTime + DISTRIBUTION_PERIOD;
    }

    function _tryRewardAndStartNewEpoch() internal {
        if (!_epochHasEnded()) return;

        address[TOP_CONTRIBUTORS_COUNT] memory topProviders = _getTopLPs();
        _distributeRewards(topProviders);

        _resetState();
    }

    function getProviderInfo(
        address providerAddress
    ) external view returns (uint256, uint256) {
        LiquidityProvider storage provider = liquidityProviders[
            providerAddress
        ];
        return (provider.totalLiquidity, provider.timeWeightedLiquidity);
    }

    function _distributeRewards(
        address[TOP_CONTRIBUTORS_COUNT] memory topProviders
    ) internal {
        // Iterating backwards is more efficient, since the last element is removed from the map on each iteration.
        for (uint256 i = _tokensWithAccruedFees.size; i > 0; i--) {
            (IERC20 feeToken, ) = _tokensWithAccruedFees.at(i - 1);
            _tokensWithAccruedFees.remove(feeToken);
            uint256 amount = feeToken.balanceOf(address(this));
            if (amount > 0) {
                for (uint256 j = 0; j < TOP_CONTRIBUTORS_COUNT; j++) {
                    if (topProviders[j] != address(0)) {
                        uint256 reward = amount / TOP_CONTRIBUTORS_COUNT; // Distribute equally
                        feeToken.safeTransfer(topProviders[j], reward);
                        emit RewardsDistributed(
                            topProviders[j],
                            feeToken,
                            reward
                        );
                    }
                }
            }
        }
    }

    function _resetState() internal {
        // Reset state (start a new epoch)
        for (uint256 i = 0; i < providerAddresses.length; i++) {
            address adr = providerAddresses[i];
            liquidityProviders[adr].timeWeightedLiquidity = 0;
            liquidityProviders[adr].totalLiquidity = 0;
            liquidityProviders[adr].lastUpdateTime = block.timestamp;
        }
        lastDistributionTime = block.timestamp;
        epochs++;
    }

    function _getTopLPs()
        internal
        view
        returns (address[TOP_CONTRIBUTORS_COUNT] memory)
    {
        address[TOP_CONTRIBUTORS_COUNT] memory topProviders;
        uint256[TOP_CONTRIBUTORS_COUNT] memory topAmounts;

        for (uint i = 0; i < providerAddresses.length; i++) {
            address lpAddress = providerAddresses[i];
            uint256 amount = liquidityProviders[lpAddress]
                .timeWeightedLiquidity;

            for (uint j = 0; j < TOP_CONTRIBUTORS_COUNT; j++) {
                if (amount > topAmounts[j]) {
                    for (uint k = TOP_CONTRIBUTORS_COUNT - 1; k > j; k--) {
                        topAmounts[k] = topAmounts[k - 1];
                        topProviders[k] = topProviders[k - 1];
                    }
                    topAmounts[j] = amount;
                    topProviders[j] = lpAddress;
                    break;
                }
            }
        }

        return topProviders;
    }

    function getTopLPs()
        external
        view
        returns (address[TOP_CONTRIBUTORS_COUNT] memory)
    {
        return _getTopLPs();
    }

    function getTimeUntilNextDistribution() external view returns (uint256) {
        uint256 nextDistributionTime = lastDistributionTime +
            DISTRIBUTION_PERIOD;
        return
            block.timestamp < nextDistributionTime
                ? nextDistributionTime - block.timestamp
                : 0;
    }

    function setHookSwapFeePercentage(
        uint64 newSwapFeePercentage
    ) external onlyOwner {
        swapFeePercentage = newSwapFeePercentage;
    }

    function setDistributionPeriod(
        uint256 newDistributionPeriod
    ) external onlyOwner {
        DISTRIBUTION_PERIOD = newDistributionPeriod;
    }
}
