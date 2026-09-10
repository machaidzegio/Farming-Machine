// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Uniswap v4-ის ძირითადი ინტერფეისები
interface IPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hook;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
}

interface IHooks {
    struct Permissions {
        bool beforeInitialize;
        bool afterInitialize;
        bool beforeAddLiquidity;
        bool afterAddLiquidity;
        bool beforeRemoveLiquidity;
        bool afterRemoveLiquidity;
        bool beforeSwap;
        bool afterSwap;
        bool beforeDonate;
        bool afterDonate;
        bool beforeSwapReturnDelta;
        bool afterSwapReturnDelta;
        bool afterAddLiquidityReturnDelta;
        bool afterRemoveLiquidityReturnDelta;
    }
}

/// @notice Base Hook კონტრაქტის სტრუქტურა
abstract contract BaseHook is IHooks {
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    modifier onlyPoolManager() {
        require(msg.sender == address(poolManager), "Not PoolManager");
        _;
    }

    function getHookPermissions() public pure virtual returns (IHooks.Permissions memory);
}

/// @title Clanker Dynamic Fee Hook V2
/// @notice დინამიური საკომისიოს ჰუკი 0.05%-დან (500) 0.28%-მდე (2800)
contract ClankerHookDynamicFeeV2 is BaseHook {
    // 0.05% = 500 (1000000-ის მასშტაბში)
    uint24 public constant BASE_FEE = 500;
    // 0.28% = 2800
    uint24 public constant MAX_FEE = 2800;

    // ბოლო ტრანზაქციის დრო და მოცულობის მონიტორინგი
    uint256 public lastSwapTimestamp;
    uint24 public currentDynamicFee;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        lastSwapTimestamp = block.timestamp;
        currentDynamicFee = BASE_FEE;
    }

    /// @notice განაზღვრავს ჰუკის უფლებებს - ჩართულია მხოლოდ beforeSwap
    function getHookPermissions() public pure override returns (IHooks.Permissions memory) {
        return IHooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true, // დინამიური საკომისიოს გამოთვლა Swap-ის წინ
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice სვაპის წინ ითვლის დინამიურ საკომისიოს ვოლატილობის მიხედვით
    function beforeSwap(
        address,
        IPoolManager.PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external onlyPoolManager returns (bytes4, int256, uint24) {
        uint256 timePassed = block.timestamp - lastSwapTimestamp;
        
        // თუ ტრანზაქციებს შორის მცირე დროა (მაღალი აქტივობა/ვოლატილობა), Fee იზრდება MAX_FEE-მდე
        if (timePassed < 15 seconds) {
            currentDynamicFee = MAX_FEE;
        } else {
            // წყნარ ბაზარზე უბრუნდება BASE_FEE-ს (0.05%)
            currentDynamicFee = BASE_FEE;
        }

        lastSwapTimestamp = block.timestamp;

        // აბრუნებს 4-ბაიტიან სელექტორს და override LP fee-ს
        return (this.beforeSwap.selector, 0, currentDynamicFee);
    }
}
