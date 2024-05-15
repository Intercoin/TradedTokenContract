// SPDX-License-Identifier: AGPL
pragma solidity 0.8.24;

/**
 * @title TradedTokenContract
 * @notice A token designed to be traded on decentralized exchanges
*    in an orderly and safe way with multiple guarantees.
 * @dev Works best with Uniswap v2 and its clones, like Pancakeswap
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "@intercoin/liquidity/contracts/interfaces/ILiquidityLib.sol";

import "./libs/FixedPoint.sol";
import "./libs/TaxesLib.sol";
import "./minimums/libs/MinimumsLib.sol";
import "./helpers/Liquidity.sol";

import "./interfaces/IPresale.sol";

import "./interfaces/ITradedToken.sol";
import "./interfaces/ITokenExchange.sol";

import "hardhat/console.sol";

contract TradedToken is Ownable, IERC777Recipient, IERC777Sender, ERC777, ReentrancyGuard, ITradedToken {
   // using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    using SafeERC20 for ERC777;
    using Address for address;
    using TaxesLib for TaxesLib.TaxesInfo;

    ILiquidityLib public immutable liquidityLib;

    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }

    struct Observation {
        uint64 timestampLast;
        uint256 price0CumulativeLast;
        FixedPoint.uq112x112 price0Average;
    }
    
    struct ClaimSettings {
        PriceNumDen minClaimPrice;
        PriceNumDen minClaimPriceGrow;
    }

    TaxesLib.TaxesInfo public taxesInfo;
    
    struct Bucket {
        uint256 remainingToSell;
        uint64 lastBucketTime;
    }
    mapping (address => Bucket) private _buckets;

    struct RateLimit {
        uint32 duration; // for time ranges, 32 bits are enough, can also define constants like DAY, WEEK, MONTH
        uint32 fraction; // out of 10,000
    }
    RateLimit public panicSellRateLimit;

    struct TaxStruct {
        uint16 buyTaxMax;
        uint16 sellTaxMax;
        uint16 holdersMax;
    }
    struct BuySellStruct {
        address buySellToken;
        uint256 buyPrice;
        uint256 sellPrice;
    }

    struct CommonSettings {
        string tokenName;
        string tokenSymbol;
        address reserveToken; //” (USDC)
        uint256 priceDrop;
        uint64 lockupDays;
    }
    
    struct Emission{
        uint128 amount; // of tokens
        uint32 frequency; // in seconds
        uint32 period; // in seconds
        uint32 decrease; // out of FRACTION 10,000
        int32 priceGainMinimum; // out of FRACTION 10,000
    }

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    
    uint64 public claimsEnabledTime;
  
    /**
     * 
     * @notice traded token address
     */
    address public immutable tradedToken;

    /**
     * 
     * @notice reserve token address
     */
    address public immutable reserveToken;

    /**
     * 
     * @notice price drop (mul by fraction)
     */
    uint256 public immutable priceDrop;

    PriceNumDen minClaimPrice;
    uint64 internal lastMinClaimPriceUpdatedTime;
    PriceNumDen minClaimPriceGrow;

    /**
     * 
     * @notice uniswap v2 pair
     */
    address public immutable uniswapV2Pair;

    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    uint256 internal k1;
    uint256 internal k2;
    uint256 internal k3;
    uint256 internal k4;

    // keep gas when try to get reserves
    // if token01 == true then (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) so reserve0 it's reserves of TradedToken
    bool internal immutable token01;
    bool internal buyPaused;
    bool private addedInitialLiquidityRun;

    uint64 internal constant MIN_CLAIM_PRICE_UPDATED_TIME = 1 days;
    uint64 internal constant AVERAGE_PRICE_WINDOW = 5;
    uint64 internal constant FRACTION = 10000;
    uint64 internal constant LOCKUP_INTERVAL = 1 days; //24 * 60 * 60; // day in seconds
    uint64 internal constant MAX_TRANSFER_COUNT = 4; // minimum transfers count until user can send to other user above own minimum lockup
    uint64 internal immutable startupTimestamp;
    uint64 internal immutable lockupDays;

    uint16 public immutable buyTaxMax;
    uint16 public immutable sellTaxMax;
    uint16 public holdersMax;
    uint16 public holdersCount;
    uint256 public holdersThreshold;

    uint256 public totalBought;
    uint256 public totalCumulativeClaimed;

    /**
     * @notice address of token used to buy and sell, default is native coin
     */
    address public immutable buySellToken;
    /**
     * @notice TradedToken buy price in buySellToken, 0 means BuySellNotAvailable
     */
    uint256 public buyPrice;
    /**
     * @notice TradedToken sell price in buySellToken, should be less than buyPrice
     */
    uint256 public sellPrice;

    Liquidity internal internalLiquidity;
    Observation internal pairObservation;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    mapping(address => uint64) public managers;
    mapping(address => uint64) public presales;
    mapping(address => uint64) public sales;
    mapping(address => uint64) public receivedTransfersCount;

    Emission internal emission;
    uint32 internal blockTimestampLast;
    uint256 internal priceReservedCumulativeLast;
    uint256 internal twapPriceLast;
    uint256 internal amountClaimedInLastPeriod;
    uint32 internal frequencyInLastPeriod;
 
    event AddedLiquidity(uint256 tradedTokenAmount, uint256 priceAverageData);
    event AddedManager(address account, address sender);
    event RemovedManager(address account, address sender);
    event AddedInitialLiquidity(uint256 tradedTokenAmount, uint256 reserveTokenAmount);
    event UpdatedTaxes(uint256 sellTax, uint256 buyTax);
    event Claimed(address account, uint256 amount);
    event Presale(address account, uint256 amount);
    event PresaleTokensBurned(address account, uint256 burnedAmount);
    event Sale(address saleContract, uint64 lockupDays);
    event PanicSellRateExceeded(address indexed holder, address indexed recipient, uint256 amount);
    event IncreasedHoldersMax(uint16 newHoldersMax);
    event IncreasedHoldersThreshold(uint256 newHoldersThreshold);
    event ClaimsEnabled(uint64 claimsEnabledTime);

    error AlreadyCalled();
    error InitialLiquidityRequired();
    error BeforeInitialLiquidityRequired();
    error ReserveTokenInvalid();
    error BadAmount();
    error NeedsApproval();
    error EmptyAddress();
    error EmptyAccountAddress();
    error EmptyManagerAddress();
    error InputAmountCanNotBeZero();
    error ZeroDenominator();
    error InsufficientAmount();
    error TaxesTooHigh();
    error PriceDropTooBig();
    error OwnerAndManagersOnly();
    error ManagersOnly();
    error OwnersOnly();
    error CantCreatePair(address tradedToken, address reserveToken);
    error EmptyReserves();
    error ClaimValidationError();
    error PriceMayBecomeLowerThanMinClaimPrice();
    error ClaimsDisabled();
    error ClaimsEnabledTimeAlreadySetup();
    error ShouldBeMoreThanMinClaimPrice();
    error MinClaimPriceGrowTooFast();
    error MaxHoldersCountExceeded(uint256 count);
    error InvalidSellRateLimitFraction();
    error BuySellNotAvailable();

    /**
     * @param commonSettings imploded common variables to variables to avoid stuck too deep error
     *      tokenName_ token name
     *      tokenSymbol_ token symbol
     *      reserveToken_ reserve token address
     *      priceDrop_ price drop while add liquidity
     *      lockupDays_ interval amount in days (see minimum lib)
     * @param claimSettings struct of claim settings
     * @param claimSettings.minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
     * @param claimSettings.minClaimPriceGrow_ (numerator,denominator) minimum claim price grow
     * @param panicSellRateLimit_ (fraction, duration) if fraction != 0, can sell at most this fraction of balance per interval with this duration
     * @param taxStruct imploded variables to avoid stuck too deep error
     *      buyTaxMax - buyTaxMax
     *      sellTaxMax - sellTaxMax
     *      holdersMax - the maximum number of holders, may be increased by owner later
     * @param buySellStruct  imploded variables to avoid stuck too deep error
     *      buySellToken - token's address is a paying token 
     *      buyPrice - buy price
     *      sellPrice - sell price
     */
    constructor(
        CommonSettings memory commonSettings,
        ClaimSettings memory claimSettings,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        TaxStruct memory taxStruct,
        BuySellStruct memory buySellStruct,
        Emission memory emission_,
        address liquidityLib_
    ) ERC777(commonSettings.tokenName, commonSettings.tokenSymbol, new address[](0)) {

        //setup
        (buyTaxMax,  sellTaxMax,  holdersMax,  buySellToken,  buyPrice,  sellPrice) =
        (taxStruct.buyTaxMax, taxStruct.sellTaxMax, taxStruct.holdersMax, buySellStruct.buySellToken, buySellStruct.buyPrice, buySellStruct.sellPrice);

        tradedToken = address(this);
        reserveToken = commonSettings.reserveToken;

        startupTimestamp = _currentBlockTimestamp();
        pairObservation.timestampLast = _currentBlockTimestamp();
        
        // setup swap addresses
        liquidityLib = ILiquidityLib(liquidityLib_);
        (uniswapRouter, uniswapRouterFactory) = liquidityLib.uniswapSettings();
        (k1, k2, k3, k4,/*k5*/,/*k6*/) = liquidityLib.koefficients();

        priceDrop = commonSettings.priceDrop;
        lockupDays = commonSettings.lockupDays;
        
        minClaimPriceGrow.numerator = claimSettings.minClaimPriceGrow.numerator;
        minClaimPriceGrow.denominator = claimSettings.minClaimPriceGrow.denominator;
        minClaimPrice.numerator = claimSettings.minClaimPrice.numerator;
        minClaimPrice.denominator = claimSettings.minClaimPrice.denominator;

        panicSellRateLimit.duration = panicSellRateLimit_.duration;
        panicSellRateLimit.fraction = panicSellRateLimit_.fraction;

        lastMinClaimPriceUpdatedTime = _currentBlockTimestamp();

        taxesInfo.init(taxesInfoInit);

        emission = emission_;

        //validations
        if (sellPrice > buyPrice) {
            revert BuySellNotAvailable();
        }
        if (
            claimSettings.minClaimPriceGrow.denominator == 0 ||
            claimSettings.minClaimPrice.denominator == 0
        ) { 
            revert ZeroDenominator();
        }

        if (reserveToken == address(0)) {
            revert ReserveTokenInvalid();
        }

        if (commonSettings.reserveToken == address(0)) {
            revert EmptyAddress();
        }

        // check inputs
        if (uniswapRouter == address(0) || uniswapRouterFactory == address(0)) {
            revert EmptyAddress();
        }
       
        if (buyTaxMax > FRACTION || sellTaxMax > FRACTION) {
            revert TaxesTooHigh();
        }

        if (panicSellRateLimit_.fraction > FRACTION) {
            revert InvalidSellRateLimitFraction();
        }
        

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        //create Pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);

        if (uniswapV2Pair == address(0)) {
            revert CantCreatePair(tradedToken, reserveToken);
        }

        token01 = (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken);

        internalLiquidity = new Liquidity(tradedToken, reserveToken, uniswapRouter);

        
    }

    ////////////////////////////////////////////////////////////////////////
    // external section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    /**
     * @notice part of IERC777Recipient
     */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

    /**
     * @notice part of IERC777Sender
     */
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

    /**
     * @notice used to add a manager to the contract, who can
     *   take certain actions even after ownership is renounced
     * @param manager the manager's address
     */
    function addManager(
        address manager
    )
        external
        onlyOwner
    {
        if (manager == address(0)) {revert EmptyManagerAddress();}
        managers[manager] = _currentBlockTimestamp();

        emit AddedManager(manager, _msgSender());
    }

    /**
     * @notice used to remove a manager to the contract, who can
     *   take certain actions even after ownership is renounced
     * @param managers_ array of manager addresses
     */
    function removeManagers(
        address[] memory managers_
    )
        external
        onlyOwner
    {
        for (uint256 i = 0; i < managers_.length; i++) {
            if (managers_[i] == address(0)) {revert EmptyManagerAddress();            }
            delete managers[managers_[i]];
            emit RemovedManager(managers_[i], _msgSender());
        }
    }

    /**
     * @notice set taxes that are burned when buying/selling
     *  from Uniswap v2 liquidity pool. Callable by owner.
     * @param newBuyTax Buy tax
     * @param newSellTax Sell tax
     * 
     */
    function setTaxes(uint16 newBuyTax, uint16 newSellTax) external onlyOwner {
        if (newBuyTax > buyTaxMax || newSellTax > sellTaxMax) {
            revert TaxesTooHigh();
        }

        taxesInfo.setTaxes(newBuyTax, newSellTax);
        emit UpdatedTaxes(taxesInfo.toSellTax, taxesInfo.toBuyTax);
    }
    
    /**
     * @notice increase the maximum number of holders of the token,
     *   which may be capped for legal reasons. A initial holdersMax of 0
     *   means there is no restriction on max holders.
     * @param newMax The new maximum amount of holders, must be higher than before
     * 
     */
    function increaseHoldersMax(uint16 newMax) external onlyOwner {
        if (newMax > holdersMax && holdersMax != 0) {
            holdersMax = newMax;
            emit IncreasedHoldersMax(holdersMax);
        }        
    }

    /**
     * @notice increase the threshold of what counts as a holder.
     *   By default, the threshold is 0, meaning any nonzero balance
     *   makes someone a holder.
     * @param newThreshold The new threshold
     * 
     */
    function increaseHoldersThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold > holdersThreshold) {
            holdersThreshold = newThreshold;
            emit IncreasedHoldersThreshold(holdersThreshold);
        }        
    }

    /**
     * @notice adds initial liquidity to a Uniswap v2 liquidity pool,
     *   which enables trading to take place. Subsequent liquidity
     *   can be added gradually by calling addLiquidity.
     *   Only callable by owner or managers.
     * @param amountTradedToken initial amount of traded tokens
     * @param amountReserveToken initial amount of reserve tokens
     * 
     */
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external {
        onlyOwnerAndManagers();
        addLiquidityOnlyOnce();
        if (amountTradedToken == 0 || amountReserveToken == 0) {
            revert ZeroDenominator();
        }
        if (amountReserveToken > ERC777(reserveToken).balanceOf(address(this))) {
            revert InsufficientAmount();
        }

        _claim(amountTradedToken, address(this));

        ERC777(tradedToken).safeTransfer(address(internalLiquidity), amountTradedToken);
        ERC777(reserveToken).safeTransfer(address(internalLiquidity), amountReserveToken);

        internalLiquidity.addLiquidity();

        // update initial prices
        uint112 reserve0; 
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast, priceReservedCumulativeLast) = _uniswapReserves();
       
        // // update
        //priceReservedCumulativeLast = uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0));
        priceReservedCumulativeLast = (uint224(reserve1) * (2**112))/uint224(reserve0);
        twapPriceLast = priceReservedCumulativeLast;
        //blockTimestampLast = _blockTimestampLast;

        // //---------------------

        emit AddedInitialLiquidity(amountTradedToken, amountReserveToken);
    }

    /**
     * @notice mint some tokens into the account, subject to limits,
     *   only callable by owner or managers
     * @param tradedTokenAmount amount to attempt to claim
     * @param account the account to mint the tokens to
     * 
     */
    function claim(uint256 tradedTokenAmount, address account) external {
        onlyOwnerAndManagers();
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account);
    }

    function enableClaims() external onlyOwner {
        if (claimsEnabledTime != 0) {
            revert ClaimsEnabledTimeAlreadySetup();
        }
        claimsEnabledTime = uint64(block.timestamp);
        emit ClaimsEnabled(claimsEnabledTime);
    }

    function availableToClaim() public view returns(uint256 tradedTokenAmount) {
        bool priceMayBecomeLowerThanMinClaimPrice;
        (tradedTokenAmount,,priceMayBecomeLowerThanMinClaimPrice,,,,,,,) = _availableToClaim(0);
        if (priceMayBecomeLowerThanMinClaimPrice) {
            tradedTokenAmount = 0;
        }

    }

    /**
    if amountIn == 0 we will try as max as possible
    */
    function _availableToClaim(
        uint256 amountIn
    ) 
        internal 
        view 
        returns(
            uint256 availableToClaim_, 
            uint256 amountOut,
            bool priceMayBecomeLowerThanMinClaimPrice,
            uint112 reserve0_, 
            uint112 reserve1_, 
            uint32 _blockTimestampLast, 
            uint256 _priceReservedCumulativeLast, 
            uint256 twapPriceCurrent,
            uint256 currentAmountClaimed,
            uint32 currentFrequencyClaimed
        ) 
    {
        (reserve0_, reserve1_, _blockTimestampLast, _priceReservedCumulativeLast) = _uniswapReserves();
        
        // how much claimed in emission.period
        if (block.timestamp/emission.period*emission.period < _blockTimestampLast) {
            currentAmountClaimed = amountClaimedInLastPeriod;
            currentFrequencyClaimed = frequencyInLastPeriod;
        } else {
            currentAmountClaimed = 0;
            currentFrequencyClaimed = 0;
        }
        
        // we  can exceed emission.amount's cap and frequency
        availableToClaim_ = (currentAmountClaimed >= emission.amount) ? 0 : emission.amount - currentAmountClaimed;
        if (availableToClaim_ > 0 && currentFrequencyClaimed >= emission.frequency) {
            availableToClaim_ = 0;
        }
console.log("availableToClaim_ = ", availableToClaim_);
        if (amountIn != 0) {
            //amountIn != 0
            if (amountIn > availableToClaim_) {
                availableToClaim_ = 0;
            } else {
                availableToClaim_ = amountIn;
            }
        }
console.log("availableToClaim_ = ", availableToClaim_);
        uint256 currentIterationTotalCumulativeClaimed;
        if (availableToClaim_ > 0) {
            currentIterationTotalCumulativeClaimed = totalCumulativeClaimed + availableToClaim_;
            // amountin reservein reserveout
            amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(
                currentIterationTotalCumulativeClaimed,
                reserve0_,
                reserve1_
            );
        }
console.log("amountOut = ", amountOut);
        if (amountOut > 0 && _priceReservedCumulativeLast > 0) {
            //-----------------------------------
            // 10000 * (currentPrice - lastPrice) / lastPrice < priceGainMinimum    
            twapPriceCurrent = (_priceReservedCumulativeLast - priceReservedCumulativeLast) / (_blockTimestampLast - blockTimestampLast);

            bool sign = twapPriceCurrent >= twapPriceLast ? true : false;
            uint256 mod = sign ? twapPriceCurrent - twapPriceLast : twapPriceLast - twapPriceCurrent;

            int32 priceGain = int32(int256(FRACTION * mod / twapPriceLast)) * (sign ? int32(1) : int32(-1));
            if (priceGain < emission.priceGainMinimum) {
                availableToClaim_ = 0;
            }
        }

        if (
            //amountOut < tradedTokenAmount ||
            amountOut == 0 ||
            emission.amount < availableToClaim_ ||
            blockTimestampLast >= block.timestamp + emission.period
        ) {
            availableToClaim_ == 0;
        }

        //variables to update
        if (availableToClaim_ > 0) {
            currentAmountClaimed  += availableToClaim_;
            currentFrequencyClaimed += 1;
        }

        if (
            FixedPoint.fraction(reserve1_ - amountOut, reserve0_ + currentIterationTotalCumulativeClaimed)._x <=
            FixedPoint.fraction(minClaimPrice.numerator, minClaimPrice.denominator)._x
        ) {
            priceMayBecomeLowerThanMinClaimPrice = true;
        }
        

        // (uint112 _reserve0, uint112 _reserve1,, ) = _uniswapReserves();
        // tradedTokenAmount = (uint256(2**64) * _reserve1 * minClaimPrice.denominator / minClaimPrice.numerator )/(2**64);
        // tradedTokenAmount += totalBought * (buyPrice - sellPrice) / FRACTION;
        // if (tradedTokenAmount > _reserve0 + totalCumulativeClaimed) {
        //     tradedTokenAmount -= (_reserve0 + totalCumulativeClaimed);
        // } else {
        //     tradedTokenAmount = 0;
        // }
        
    }

    /**
     * @notice managers can restrict future claims to make sure
     *  that selling all claimed tokens will never drop price below
     *  the newMinimumPrice.
     * @param newMinimumPrice below which the token price on Uniswap v2 pair
     *  won't drop, if all claimed tokens were sold right after being minted.
     *  This price can't increase faster than minClaimPriceGrow per day.
     * 
     */
    function restrictClaiming(PriceNumDen memory newMinimumPrice) external {
        onlyManagers();
        if (newMinimumPrice.denominator == 0) {
            revert ZeroDenominator();
        }

        FixedPoint.uq112x112 memory newMinimumPriceFraction     = FixedPoint.fraction(newMinimumPrice.numerator, newMinimumPrice.denominator);
        FixedPoint.uq112x112 memory minClaimPriceFraction       = FixedPoint.fraction(minClaimPrice.numerator, minClaimPrice.denominator);
        FixedPoint.uq112x112 memory minClaimPriceGrowFraction   = FixedPoint.fraction(minClaimPriceGrow.numerator, minClaimPriceGrow.denominator);
        if (newMinimumPriceFraction._x <= minClaimPriceFraction._x) {
            revert ShouldBeMoreThanMinClaimPrice();
        }
        if (
            newMinimumPriceFraction._x - minClaimPriceFraction._x > minClaimPriceGrowFraction._x ||
            lastMinClaimPriceUpdatedTime <= block.timestamp + MIN_CLAIM_PRICE_UPDATED_TIME
        ) {
            revert MinClaimPriceGrowTooFast();
        }

        lastMinClaimPriceUpdatedTime = uint64(block.timestamp);
            
        minClaimPrice.numerator = newMinimumPrice.numerator;
        minClaimPrice.denominator = newMinimumPrice.denominator;
    }

    /**
     * @notice called by owner or managers to automatically sell some tokens and add liquidity
     * @param tradedTokenAmount the amount of tradedToken to use.
     *   Some of it is sold for reserveToken, and the rest is added, together with
     *   the obtained reserveToken, to both sides of the liquidity pool.
     *   Pass zero here to use the maximum amount.
     */
    function addLiquidity(uint256 tradedTokenAmount) external {
        initialLiquidityRequired();
        onlyOwnerAndManagers();
        
        uint256 tradedReserve1;
        uint256 tradedReserve2;
        uint256 priceAverageData; // it's fixed point uint224

        uint256 rTraded;
        uint256 rReserved;
        uint256 traded2Swap;
        uint256 traded2Liq;
        uint256 reserved2Liq;

        FixedPoint.uq112x112 memory averageWithPriceDrop;

        (tradedReserve1, tradedReserve2, priceAverageData) = _maxAddLiquidity();

        bool err = (
            tradedReserve1 >= tradedReserve2 || 
            tradedTokenAmount > (tradedReserve2 - tradedReserve1)
        );

        if (!err) {
            // if tradedTokenAmount is zero, let's use the maximum amount of traded tokens allowed
            if (tradedTokenAmount == 0) {
                tradedTokenAmount = tradedReserve2 - tradedReserve1;
            }

            (rTraded, rReserved, traded2Swap, traded2Liq, reserved2Liq) = _calculateSellTradedAndLiquidity(
                tradedTokenAmount
            );

            averageWithPriceDrop = (
                FixedPoint.muluq(
                    FixedPoint.uq112x112(uint224(priceAverageData)),
                    FixedPoint.muluq(
                        FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)),
                        FixedPoint.fraction(1, FRACTION)
                    )   
                )
                    
            );

            // "new_current_price" should be more than "average_price(1-price_drop)"
            if (
                FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x <=
                averageWithPriceDrop._x
            ) {
                err = true;
            }
        }

        if (err) {
            revert PriceDropTooBig();
        }

        // trade trade tokens and add liquidity
        _doSellTradedAndLiquidity(traded2Swap, traded2Liq);

        emit AddedLiquidity(tradedTokenAmount, priceAverageData);

        _update();
    }

    ////////////////////////////////////////////////////////////////////////
    // public section //////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    
    /**
     * @notice standard ERC-20 function called by token holder to transfer some amount to recipient
     * @param recipient who to transfer to
     * @param amount the amount to transfer
     * @return bool returns true if transfer is successful
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        // inject into transfer and burn tax from sender
        // two ways:
        // 1. make calculations, burn taxes from sender and do transaction with subtracted values
        if (uniswapV2Pair == _msgSender()) {
            if(!addedInitialLiquidityRun) {
                // prevent added liquidity manually with presale tokens (before adding initial liquidity from here)
                revert InitialLiquidityRequired();
            }
            amount = _burnTaxes(_msgSender(), amount, buyTax());
        } else {
            //The way a user sends tokens directly to a Uniswap pair in the hope of executing a flash swap.
            amount = _handleTransferToUniswap(_msgSender(), recipient, amount);
        }

        return super.transfer(recipient, amount);

        // 2. do usual transaction, then make calculation and burn tax from sides(buyer or seller)
        // we DON'T USE this case, because have callbacks in _move method: _callTokensToSend and _callTokensReceived
        // and than be send to some1 else in recipient contract callback
    }

    /**
     * @notice standard ERC-20 function called to transfer some amount from holder to recipient
     * @param holder from whom to transfer
     * @param recipient who to transfer to
     * @param amount the amount to transfer
     * @return bool returns true if transfer is successful
     */
    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        
        amount = _handleTransferToUniswap(holder, recipient, amount);
        
        return super.transferFrom(holder, recipient, amount);
    }

    /**
     * @notice burn taxes during a transfer
     * @param holder from whom to transfer
     * @param amount the amount to transfer
     * @param tax the fraction out of 10000 representing the tax
     * @return amount remaining
     */
    function _burnTaxes(address holder, uint256 amount, uint16 tax) internal returns(uint256) {
        uint256 taxAmount = (amount * tax) / FRACTION;
        if (taxAmount != 0) {
            amount -= taxAmount;
            _burn(holder, taxAmount, "", "");
        }
        return amount > 1 ? amount : 1; // to avoid transferring 0 in edge cases, transfer a tiny amount
    }

    /**
     * @notice get the current buy tax
     * @return the fraction out of 10000 representing the tax
     */
    function buyTax() public view returns(uint16) {
        return taxesInfo.buyTax();
    }

    /**
     * @notice get the current sell tax
     * @return the fraction out of 10000 representing the tax
     */
    function sellTax() public view returns(uint16) {
        return taxesInfo.sellTax();
    }

    /**
     * @notice used to buy tokens for a fixed price in reserveToken
     */
    function buy(uint256 amount) public payable {
        if (buyPrice == 0 || buyPaused) {
            revert BuySellNotAvailable();
        }

        if (buySellToken == address(0)) {
            amount = msg.value;
        } else {
            IERC20(buySellToken).transferFrom(msg.sender, address(this), amount);
        }
        _mint(msg.sender, amount * FRACTION / buyPrice, "", "");
        totalBought += amount;
    }

    /**
     * @notice used to sell TradedTokens for a fixed price in reserveToken
     */
    function sell(uint256 amount) public {
        if (sellPrice == 0) {
            revert BuySellNotAvailable();
        }
        uint256 out = amount * sellPrice / FRACTION;
        if (buySellToken == address(0)) {
            if (address(this).balance < out) {
                revert InsufficientAmount();
            }
            // see https://ethereum.stackexchange.com/a/56760/19734
            (bool sent, bytes memory data) = address(msg.sender).call{value: out}("");
            if (!sent) {
                revert BuySellNotAvailable();
            }
        } else {
            if (IERC20(buySellToken).balanceOf(address(this)) < out) {
                revert InsufficientAmount();
            }
            IERC20(buySellToken).transfer(msg.sender, amount);
        }
    }

    /**
     * @notice used to pause buying, e.g. if buySellToken is compromised
     */
    function pauseBuy(bool status) public {
        onlyOwnerAndManagers();
        buyPaused = status;
    }

    /**
     * @notice register a presale that can take place before trading begins
     * @dev The presale contract must have a method called endTime() which returns uint64 timestamp,
     *  and which occurs at least two hours after block.timestamp
     * @param contract_ the address of the contract that will manage the presale.
     * @param amount amount of tokens to mint to the contract, this is the maximum taht can be sold in the presale
     * @param presaleLockupDays the number of days people who obtained the token in the presale cannot transfer tokens for
     */
    function startPresale(address contract_, uint256 amount, uint64 presaleLockupDays) public onlyOwner {

        onlyBeforeInitialLiquidity();
        if (contract_ == address(0)) {
            revert EmptyAddress();
        }
        uint64 endTime = IPresale(contract_).endTime();

        // give at least two hours for the presale because burnRemaining can be called in the second hour
        if (block.timestamp < endTime - 3600 * 2) {
            _mint(contract_, amount, "", "");
            presales[contract_] = sales[contract_] = presaleLockupDays;
            emit Presale(contract_, amount);
        }
    }
	
    /**
    * @notice owner of a smart contract can designate it as a Sale contract
	*   to enforce lockups and exclude it from MaxHolders checks
    * @param contract_ the sale contract but msg.sender must be the owner
    * @param saleLockupDays the number of days people who obtained the token in the sale cannot transfer tokens for
    */
	function startSale(address contract_, uint64 saleLockupDays) public {

        if (contract_ == address(0)) {
            revert EmptyAddress();
        }
        
        if (Ownable(contract_).owner() != msg.sender) {
			revert OwnersOnly();
		}
        
		if (sales[contract_] != 0) {
			revert AlreadyCalled();
		}
		sales[contract_] = saleLockupDays;
		emit Sale(contract_, saleLockupDays);
	}

    /**
    * @notice starting one hour before a presale's endTime(),
    *  anyone can call this function to burn its remaining tokens.
    *  Someone should do it before endTime() in case the presale
    *  contract allows someone to withdraw the remianing tokens later.
    * @param contract_ the presale contract
    */
    function burnRemaining(address contract_) public {
        uint64 endTime = IPresale(contract_).endTime();

        // allow it one hour before the endTime, so owner can't withdraw money
        if (block.timestamp <= endTime - 3600) {
            return;
        }

        uint256 toBurn = balanceOf(contract_);
        if (toBurn == 0) {
            return;
        }

        _burn(contract_, toBurn, "", "");
        emit PresaleTokensBurned(contract_, toBurn);
        
    }

    function getLockedAmount(address from) public view returns(uint256) {
        return tokensLocked[from]._getMinimum();
    }

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    function _preventPanic(
        address holder,
        address recipient,
        uint256 amount
    ) 
        internal 
        returns(uint256 adjustedAmount)
    {
        if (
            holder == address(internalLiquidity) ||
            recipient == address(internalLiquidity) ||
            panicSellRateLimit.fraction == 0 ||
            panicSellRateLimit.duration == 0

        ) {
            return amount;
        }
        
        uint256 currentBalance = balanceOf(holder);

        if (block.timestamp / panicSellRateLimit.duration * panicSellRateLimit.duration > _buckets[holder].lastBucketTime) {
            _buckets[holder].lastBucketTime = uint64(block.timestamp);
            _buckets[holder].remainingToSell = currentBalance * panicSellRateLimit.fraction / FRACTION;
        }

        if (_buckets[holder].remainingToSell == 0) {
            emit PanicSellRateExceeded(holder, recipient, amount);
            return 5;
        } else if (_buckets[holder].remainingToSell >= amount) {
            _buckets[holder].remainingToSell -= amount;
            return amount;
        } else {
            return _buckets[holder].remainingToSell;
        }
    }

    function holdersCheckBeforeTransfer(address from, address to, uint256 amount) internal {
        
        if (to != address(0)) {
        
            uint256 toBalanceOf = balanceOf(to);

            if (
                toBalanceOf <= holdersThreshold && 
                toBalanceOf + amount > holdersThreshold           
            ) {

				if (sales[to] == 0) {
					++holdersCount;
				}

                if (holdersMax != 0) {
                    // onlyOwnerAndManagers and internalLiquidity and presales
                    // with lockups can send tokens to new users, in that case.
                    // here we exclude transactions such as:
                    // 1. address(this) -> internalLiquidity
                    // 2. internalLiquidity -> uniswap
                    // 3. presale -> early buyer of locked-up tokens
                    if (from != address(this)
                    && from != address(internalLiquidity)
                    && from != address(0)
                    && presales[from] == 0
					&& sales[to] == 0) {
                        onlyOwnerAndManagers();
                    }
                    
                    if (holdersCount > holdersMax) {
                        revert MaxHoldersCountExceeded(holdersMax);
                    }
                }
            }
        }

        if (from != address(0)) {
            uint256 fromBalanceOf = balanceOf(from);
            if (fromBalanceOf < amount) {
                // will revert inside transferFrom or transfer method
            } else {
                if (
                    fromBalanceOf > holdersThreshold
                    && fromBalanceOf - amount <= holdersThreshold
                    
                ) {
                    if ((sales[from]) == 0) {
                        --holdersCount;
                    }
                }
            }
        }
    }
    // either owner or managers
    function onlyOwnerAndManagers() internal view {
        if (owner() != _msgSender() && managers[_msgSender()] == 0) {
            revert OwnerAndManagersOnly();
        }
    }
    // only managers without owner
    function onlyManagers() internal view {
        if (managers[_msgSender()] == 0) {
            revert ManagersOnly();
        }
    }
    // can only add liquidity once
    function addLiquidityOnlyOnce() internal {
        if (addedInitialLiquidityRun) {
            revert AlreadyCalled();
        }
        addedInitialLiquidityRun = true;
    }
    // after initial liquidity was added
    function initialLiquidityRequired() internal view {
        if (!addedInitialLiquidityRun) {
            revert InitialLiquidityRequired();
        }
    }
    // before initial liquidity was added
    function onlyBeforeInitialLiquidity() internal view{
        if (addedInitialLiquidityRun) {
            revert BeforeInitialLiquidityRequired();
        }
    }
    // called before any transfer
    function _beforeTokenTransfer(
        address /*operator*/,
        address from,
        address to,
        uint256 amount
    ) internal virtual override {

        holdersCheckBeforeTransfer(from, to, amount);
        if (sales[from] != 0) {
            tokensLocked[to]._minimumsAdd(amount, sales[from], LOCKUP_INTERVAL, true);
        } 
        if (
            // if minted
            (from == address(0)) ||
            // or burnt itself
            (from == address(this) && to == address(0)) // ||
        ) {
            //skip validation
        } else {
            uint256 balance = balanceOf(from);
            uint256 locked = tokensLocked[from]._getMinimum();
            // if (balance - locked < amount) {
            //     revert InsufficientAmount();
            // }
            bool isLocked = (balance - locked < amount);
            // if ((receivedTransfersCount[from] >= MAX_TRANSFER_COUNT) && isLocked) {
            //     revert InsufficientAmount();
            // }
            if (isLocked) {
                //tokensLocked[from].minimumsTransfer(tokensLocked[to], false, amount);
                if ((receivedTransfersCount[from] < MAX_TRANSFER_COUNT) && (balance >= amount)) {
                    // pass
                    tokensLocked[from].minimumsTransfer(tokensLocked[to], false, amount);
                } else {
                    revert InsufficientAmount();
                }
            }
 
            if (receivedTransfersCount[from] < MAX_TRANSFER_COUNT) {
                receivedTransfersCount[from] += 1;
            }
        }
        
    }

    /**
     * @notice helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**64 - 1]
     */
    function _currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    /**
     * @notice wrapper for getting uniswap reserves function. we use `token01` var here to be sure that reserve0 and token0 are always traded token data
     */
    function _uniswapReserves()
        internal
        view
        returns (
            // reserveTraded, reserveReserved, blockTimestampLast, priceReservedCumulativeLast
            uint112,
            uint112,
            uint32,
            uint256
        )
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast_) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            revert EmptyReserves();
        }

        uint256 priceCumulativeLast;
        if (token01) {
            priceCumulativeLast = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
            return (reserve0, reserve1, blockTimestampLast_, priceCumulativeLast);
        } else {
            priceCumulativeLast = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
            return (reserve1, reserve0, blockTimestampLast_, priceCumulativeLast);
        }
    }

    //function _validateEmission
    function _validateClaim(uint256 tradedTokenAmount) internal {

        if (claimsEnabledTime == 0) {
            revert ClaimsDisabled();
        }

        if (tradedTokenAmount == 0) {
            revert InputAmountCanNotBeZero();
        }

        (   
            uint256 availableToClaim_,
            uint256 amountOut, 
            bool priceMayBecomeLowerThanMinClaimPrice,
            uint112 _reserve0, 
            uint112 _reserve1, 
            uint32 blockTimestampCurrent, 
            uint256 priceReservedCumulativeCurrent, 
            uint256 twapPriceCurrent,
            uint256 currentAmountClaimed,
            uint32 currentFrequencyClaimed
        ) = _availableToClaim(tradedTokenAmount);

        //revert if (amountOut == 0 || amountOut < tradedTokenAmount) {
        if (
            amountOut == 0 ||
            availableToClaim_ < tradedTokenAmount
        ) {
            revert ClaimValidationError();
        }
  
        // update twap price and emission things
        twapPriceLast = twapPriceCurrent;
        blockTimestampLast = blockTimestampCurrent;
        priceReservedCumulativeLast = priceReservedCumulativeCurrent;
        amountClaimedInLastPeriod = currentAmountClaimed;
        frequencyInLastPeriod = currentFrequencyClaimed;

        
        if (priceMayBecomeLowerThanMinClaimPrice) {
            revert PriceMayBecomeLowerThanMinClaimPrice();
        }
    }
    
    /**
     * @notice do claim to the `account` and locked tokens if
     */
    function _claim(uint256 tradedTokenAmount, address account) internal {
        
        if (account == address(0)) {
            revert EmptyAccountAddress();
        }

        totalCumulativeClaimed += tradedTokenAmount;

        _mint(account, tradedTokenAmount, "", "");
        
        emit Claimed(account, tradedTokenAmount);

        address sender = _msgSender();
        // _handleTransferToUniswap tokens for any except:
        // - owner(because it's owner)
        // - current contract(because do sell traded tokens and add liquidity)
        // - managers (like ClaimManager or StakeManager)
        if (
            sender != owner() && 
            account != address(this) &&
            managers[sender] == 0
        ) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupDays, LOCKUP_INTERVAL, true);
        }

    }

    function _handleTransferToUniswap(address holder, address recipient, uint256 amount) private returns(uint256) {
        if (recipient.isContract()) {
            try IUniswapV2Pair(recipient).factory() returns (address f) {
    
                if (f != uniswapRouterFactory) {
                    return amount;
                }
                if(!addedInitialLiquidityRun) {
                    // prevent added liquidity manually with presale tokens (before adding initial liquidity from here)
                    revert InitialLiquidityRequired();
                }
                if(holder != address(internalLiquidity)) {
                    // prevent panic when user will sell to uniswap
                    amount = _preventPanic(holder, recipient, amount);
                    // burn taxes from remainder
                    amount = _burnTaxes(holder, amount, sellTax());
                }
            } catch Error(string memory _err) {
                // do nothing
            } catch (bytes memory _err) {
                // do nothing
            }
        }
        return amount;
    }

    function _doSwapOnUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address beneficiary
    ) internal returns (uint256 amountOut) {
        if (!ERC777(tokenIn).approve(address(uniswapRouter), amountIn)) {
            revert NeedsApproval();
        }

        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
        // amountOutMin is set to 0, so only do this with pairs that have deep liquidity

        uint256[] memory outputAmounts = IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
            amountIn,
            0,
            path,
            beneficiary,
            block.timestamp
        );

        amountOut = outputAmounts[1];
    }

    function _tradedAveragePrice() internal view returns (FixedPoint.uq112x112 memory) {
        //uint64 blockTimestamp = _currentBlockTimestamp();
        uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        uint64 timeElapsed = _currentBlockTimestamp() - pairObservation.timestampLast;
        uint64 windowSize = ((_currentBlockTimestamp() - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        if (timeElapsed > windowSize
        && timeElapsed > 0
        && price0Cumulative > pairObservation.price0CumulativeLast) {
            return FixedPoint.uq112x112(
                uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed)
            );
        }
        //use stored
        return pairObservation.price0Average;
    }

    function _update() internal {
        uint64 blockTimestamp = _currentBlockTimestamp();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;

        uint64 windowSize = ((blockTimestamp - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        if (timeElapsed > windowSize && timeElapsed > 0) {
            uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
            pairObservation.price0Average = FixedPoint.divuq(
                FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast)),
                FixedPoint.encode(timeElapsed)
            );
                
            pairObservation.price0CumulativeLast = price0Cumulative;

            pairObservation.timestampLast = blockTimestamp;
        }
    }

    function _calculateSellTradedAndLiquidity(uint256 incomingTradedToken)
        internal
        view
        returns (
            uint256 rTraded,
            uint256 rReserved,
            uint256 traded2Swap,
            uint256 traded2Liq,
            uint256 reserved2Liq
        )
    {
        (
            rTraded,
            rReserved, 
            /*uint32 blockTimestampLast*/,
            /*price cumulative last*/
        ) = _uniswapReserves();
        traded2Swap = (_sqrt(rTraded*(incomingTradedToken*k1 + rTraded*k2)) - rTraded*k3) / k4;

        if (traded2Swap <= 0 || incomingTradedToken <= traded2Swap) {
            revert BadAmount();
        }

        reserved2Liq = IUniswapV2Router02(uniswapRouter).getAmountOut(traded2Swap, rTraded, rReserved);
        traded2Liq = incomingTradedToken - traded2Swap;
    }

    function _doSellTradedAndLiquidity(uint256 traded2Swap, uint256 traded2Liq) internal {
        // claim to address(this) necessary amount to swap from traded to reserved tokens
        _mint(address(this), traded2Swap, "", "");
        _doSwapOnUniswap(tradedToken, reserveToken, traded2Swap, address(internalLiquidity));

        // mint that left to  internalLiquidity contract
        _mint(address(internalLiquidity), traded2Liq, "", "");

        // add to liquidity from there
        internalLiquidity.addLiquidity();
    }

    function _maxAddLiquidity()
        internal
        view
        returns (
            //      traded1 -> traded2->priceAverageData
            uint256,
            uint256,
            uint256
        )
    {
        // tradedNew = Math.sqrt(@tokenPair.r0 * @tokenPair.r1 / (average_price*(1-@price_drop)))

        uint112 traded;
        uint112 reserved;
        uint32 blockTimestampLast_;

        (traded, reserved, blockTimestampLast_,) = _uniswapReserves();
        FixedPoint.uq112x112 memory priceAverageData = _tradedAveragePrice();

        uint256 tradedNew = FixedPoint.decode(
            FixedPoint.muluq(
                FixedPoint.muluq(
                    FixedPoint.encode(uint112(_sqrt(traded))),//q1,
                    FixedPoint.encode(uint112(_sqrt(reserved)))//q2
                ),
                FixedPoint.muluq(
                    FixedPoint.encode(uint112(_sqrt(FRACTION))),
                    FixedPoint.divuq(
                        FixedPoint.encode(uint112(1)), 
                        FixedPoint.sqrt(
                            FixedPoint.muluq(
                                priceAverageData,
                                FixedPoint.muluq(
                                    FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)),
                                    FixedPoint.fraction(1, FRACTION)
                                )
                            )
                        )
                        //q3
                    )
                )
            )
        );

        return (traded, tradedNew, priceAverageData._x);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 result) {
        if (x == 0) {
            return 0;
        }
        // Calculate the square root of the perfect square of a
        // power of two that is the closest to x.
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }
        // The operations can never overflow because the result is
        // max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }
}
