// SPDX-License-Identifier: AGPL
pragma solidity 0.8.15;

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

import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";
import "./libs/TaxesLib.sol";
import "./minimums/libs/MinimumsLib.sol";
import "./helpers/Liquidity.sol";

import "./interfaces/IPresale.sol";
import "./interfaces/IClaim.sol";

//import "hardhat/console.sol";

contract TradedToken is Ownable, IClaim, IERC777Recipient, IERC777Sender, ERC777, ReentrancyGuard {
   // using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    using SafeERC20 for ERC777;
    using Address for address;
    using TaxesLib for TaxesLib.TaxesInfo;

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
        uint256 alreadySentInCurrentBucket;
        uint64 lastBucketTime;
    }
    mapping (address => Bucket) private _buckets;

    struct RateLimit {
        uint32 duration; // for time ranges, 32 bits are enough, can also define constants like DAY, WEEK, MONTH
        uint32 fraction; // out of 10,000
    }
    RateLimit public panicSellRateLimit;

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    uint64 public claimsEnabledTime;
  
    /**
     * @custom:shortd traded token address
     * @notice traded token address
     */
    address public immutable tradedToken;

    /**
     * @custom:shortd reserve token address
     * @notice reserve token address
     */
    address public immutable reserveToken;

    /**
     * @custom:shortd price drop (mul by fraction)
     * @notice price drop (mul by fraction)
     */
    uint256 public immutable priceDrop;

    PriceNumDen minClaimPrice;
    uint64 internal lastMinClaimPriceUpdatedTime;
    PriceNumDen minClaimPriceGrow;

    /**
     * @custom:shortd uniswap v2 pair
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

    uint64 internal constant MIN_CLAIM_PRICE_UPDATED_TIME = 1 days;
    uint64 internal constant AVERAGE_PRICE_WINDOW = 5;
    uint64 internal constant FRACTION = 10000;
    uint64 internal constant LOCKUP_INTERVAL = 1 days; //24 * 60 * 60; // day in seconds
    uint64 internal immutable startupTimestamp;
    uint64 internal immutable lockupDays;

    uint16 public immutable buyTaxMax;
    uint16 public immutable sellTaxMax;
    uint256 public holdersThreshold;
    uint16 public holdersMax;
    uint16 public holdersCount;
    uint256 internal constant numDen =  18446744073709551616;//2 ** 64;

    uint256 public totalCumulativeClaimed;

    Liquidity internal internalLiquidity;
    Observation internal pairObservation;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    mapping(address => uint64) public managers;
    mapping(address => uint64) internal presales;

    bool private addedInitialLiquidityRun;

    event AddedLiquidity(uint256 tradedTokenAmount, uint256 priceAverageData);
    event AddedManager(address account, address sender);
    event RemovedManager(address account, address sender);
    event AddedInitialLiquidity(uint256 tradedTokenAmount, uint256 reserveTokenAmount);
    event UpdatedTaxes(uint256 sellTax, uint256 buyTax);
    event Claimed(address account, uint256 amount);
    event Presale(address account, uint256 amount);
    event PresaleTokensBurned(address account, uint256 burnedAmount);
    event PanicSellRateExceeded(address indexed holder, address indexed recipient, uint256 amount);
    event IncreasedHoldersMax(uint16 newHoldersMax);
    event IncreasedHoldersThreshold(uint16 newHoldersThreshold);

    error AlreadyCalled();
    error InitialLiquidityRequired();
    error BeforeInitialLiquidityRequired();
    error reserveTokenInvalid();
    error EmptyAddress();
    error EmptyAccountAddress();
    error EmptyManagerAddress();
    error EmptyTokenAddress();
    error InputAmountCanNotBeZero();
    error ZeroDenominator();
    error InsufficientAmount();
    error TaxesTooHigh();
    error PriceDropTooBig();
    error OwnerAndManagersOnly();
    error ManagersOnly();
    error CantCreatePair(address tradedToken, address reserveToken);
    error BuyTaxInvalid();
    error SellTaxInvalid();
    error EmptyReserves();
    error ClaimValidationError();
    error PriceHasBecomeALowerThanMinClaimPrice();
    error ClaimsDisabled();
    error ClaimsEnabledTimeAlreadySetup();
    error ClaimTooFast(uint256 untilTime);
    error InsufficientAmountToClaim(uint256 requested, uint256 maxAvailable);
    error ShouldBeMoreThanMinClaimPrice();
    error MinClaimPriceGrowTooFast();
    error NotAuthorized();
    error MaxHoldersCountExceeded(uint256 count);
    error SenderIsNotInWhitelist();

    /**
     * @param tokenName_ token name
     * @param tokenSymbol_ token symbol
     * @param reserveToken_ reserve token address
     * @param priceDrop_ price drop while add liquidity
     * @param lockupDays_ interval amount in days (see minimum lib)
     * @param claimSettings struct of claim settings
     * @param claimSettings.minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
     * @param claimSettings.minClaimPriceGrow_ (numerator,denominator) minimum claim price grow
     * @param panicSellRateLimit_ (fraction, duration) Implemented a bucket system to limit the increasing selling rate.
     * @param buyTaxMax_ buyTaxMax_
     * @param sellTaxMax_ sellTaxMax_
     * @param holdersMax_ the maximum number of holders, may be increased by owner later
     */
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupDays_,
        ClaimSettings memory claimSettings,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        uint16 buyTaxMax_,
        uint16 sellTaxMax_,
        uint16 holdersMax_
    ) ERC777(tokenName_, tokenSymbol_, new address[](0)) {

        //setup
        (buyTaxMax,  sellTaxMax,  holdersMax) =
        (buyTaxMax_, sellTaxMax_, holdersMax_);

        tradedToken = address(this);
        reserveToken = reserveToken_;

        startupTimestamp = _currentBlockTimestamp();
        pairObservation.timestampLast = _currentBlockTimestamp();
        
        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory, k1, k2, k3, k4) = SwapSettingsLib.netWorkSettings();

        priceDrop = priceDrop_;
        lockupDays = lockupDays_;
        
        minClaimPriceGrow.numerator = claimSettings.minClaimPriceGrow.numerator;
        minClaimPriceGrow.denominator = claimSettings.minClaimPriceGrow.denominator;
        minClaimPrice.numerator = claimSettings.minClaimPrice.numerator;
        minClaimPrice.denominator = claimSettings.minClaimPrice.denominator;

        panicSellRateLimit.duration = panicSellRateLimit_.duration;
        panicSellRateLimit.fraction = panicSellRateLimit_.fraction;

        lastMinClaimPriceUpdatedTime = _currentBlockTimestamp();

        taxesInfo.init(taxesInfoInit);

        //validations
        if (
            claimSettings.minClaimPriceGrow.denominator == 0 ||
            claimSettings.minClaimPrice.denominator == 0
        ) { 
            revert ZeroDenominator();
        }

        if (reserveToken == address(0)) {
            revert reserveTokenInvalid();
        }

        // check inputs
        if (uniswapRouter == address(0) || uniswapRouterFactory == address(0)) {
            revert EmptyAddress();
        }
       
        if (buyTaxMax > FRACTION || sellTaxMax > FRACTION) {
            revert TaxesTooHigh();
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
     * @param address the manager's address
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
     * @param address array of manager addresses
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
     * @custom:calledby owner
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
     * @custom:calledby owner
     */
    function increaseHoldersMax(uint16 newMax) external onlyOwner {
        if (newMax > holdersMax) {
            holdersMax = newMax;
            emit IncreasedHoldersMax(holdersMax);
        }        
    }

    /**
     * @notice increase the threshold of what counts as a holder.
     *   By default, the threshold is 0, meaning any nonzero balance
     *   makes someone a holder.
     * @param newMax The new maximum amount of holders, must be higher than before
     * @custom:calledby owner
     */
    function increaseHoldersThreshold(uint16 newThreshold) external onlyOwner {
        if (newThreshold > holdersThreshold) {
            holdersMax = newMax;
            emit IncreasedHoldersThreshold(holdersThreshold);
        }        
    }

    /**
     * @notice adds initial liquidity to a Uniswap v2 liquidity pool,
     *   which enables trading to take place. Subsequent liquidity
     *   can be added gradually by calling addLiquidity.
     *   Only callable by owner or managers.
     * @param newMax The new maximum amount of holders, must be higher than before
     * @custom:calledby owner or managers
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

        emit AddedInitialLiquidity(amountTradedToken, amountReserveToken);
    }

    /**
     * @notice mint some tokens into the account, subject to limits,
     *   only callable by owner or managers
     * @param tradedTokenAmount amount to attempt to claim
     * @param account the account to mint the tokens to
     * @custom:calledby owner or managers
     */
    function claim(uint256 tradedTokenAmount, address account)
        external
    {
        onlyOwnerAndManagers();
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account);
    }

    function enableClaims() external onlyOwner {
        if (claimsEnabledTime != 0) {
            revert ClaimsEnabledTimeAlreadySetup();
        }
        claimsEnabledTime = uint64(block.timestamp);
    }

    /**
     * @notice managers can restrict future claims to make sure
     *  that selling all claimed tokens will never drop price below
     *  the newMinimumPrice.
     * @param newMinimumPrice below which the token price on Uniswap v2 pair
     *  won't drop, if all claimed tokens were sold right after being minted.
     *  This price can't increase faster than minClaimPriceGrow per day.
     * @custom:calledby managers
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
     *   the obtained reserveToken, to both sides of the liquidity pool
     */
    function addLiquidity(uint256 tradedTokenAmount) external {
        initialLiquidityRequired();
        onlyOwnerAndManagers();
        if (tradedTokenAmount == 0) {
            revert InputAmountCanNotBeZero();
        }
        
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

        bool err;

        if (tradedReserve1 < tradedReserve2 && tradedTokenAmount <= (tradedReserve2 - tradedReserve1)) {
            err = false;
        } else {
            err = true;
        }

        if (!err) {
            //if zero we've try to use max as possible of available tokens
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
        }

        holdersCheckBeforeTransfer(_msgSender(), recipient, amount);

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
        
        try IUniswapV2Pair(recipient).factory() returns (address f) {
            if (f == uniswapRouterFactory) {
                if(!addedInitialLiquidityRun) {
                    // prevent added liquidity manually with presale tokens (before adding initial liquidity from here)
                    revert InitialLiquidityRequired();
                }
                if(holder != address(internalLiquidity)) {
                    amount = _burnTaxes(holder, amount, sellTax());

                    // prevent panic when user will sell to uniswap
                    amount = preventPanic(holder, recipient, amount);
                }
            }
        } catch Error(string memory _err) {
            // do nothing
        } catch (bytes memory _err) {
            // do nothing, this can happen when sending to EOA etc.
        }
        
        holdersCheckBeforeTransfer(holder, recipient, amount);
        
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
        return amount;
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
     * @notice register a presale that can take place before trading begins
     * @dev The presale contract must have a method called endTime() which returns uint64 timestamp,
     *  and which occurs at least two hours after block.timestamp
     * @param contract_ the address of the contract that will manage the presale.
     * @param amount amount of tokens to mint to the contract, this is the maximum taht can be sold in the presale
     * @param presaleLockupDays the number of days people who obtained the token in the presale cannot trade tokens for
     */
    function startPresale(address contract_, uint256 amount, uint64 presaleLockupDays) public onlyOwner {

        onlyBeforeInitialLiquidity();

        uint64 endTime = IPresale(contract_).endTime();

        // give at least two hours for the presale because burnRemaining can be called in the second hour
        if (block.timestamp < endTime - 3600 * 2) {
            _mint(contract_, amount, "", "");
            presales[contract_] = presaleLockupDays;
            emit Presale(contract_, amount);
        }
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

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    function preventPanic(
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
        uint256 max = currentBalance * panicSellRateLimit.fraction / FRACTION;

        uint32 duration = panicSellRateLimit.duration;
        duration = (duration == 0) ? 1 : duration; // make no sense if duration eq 0      

        adjustedAmount = amount;
        
        if (block.timestamp / duration * duration > _buckets[recipient].lastBucketTime) {
            _buckets[recipient].lastBucketTime = uint64(block.timestamp);
            _buckets[recipient].alreadySentInCurrentBucket = 0;
        }
        
        if (max <= _buckets[recipient].alreadySentInCurrentBucket) {
            emit PanicSellRateExceeded(holder, recipient, amount);
            return 5;
        }

        if (_buckets[recipient].alreadySentInCurrentBucket + amount <= max) {
            // proceed with transfer normally
            _buckets[recipient].alreadySentInCurrentBucket += amount;
            
        } else {

            adjustedAmount = max - _buckets[recipient].alreadySentInCurrentBucket;
            _buckets[recipient].alreadySentInCurrentBucket = max;
        }
    }

    function holdersCheckBeforeTransfer(address from, address to, uint256 amount) internal {
        if (balanceOf(to) == 0) {
            ++holdersCount;

            if (holdersMax != 0) {
                // onlyOwnerAndManagers and internalliquidity
                // send tokens to new users available only for managers and owner
                // here we exclude transactions such as:
                // 1. address(this) -> internalLiquidity
                // 2. internalLiquidity -> uniswap
                if (from != address(this) && from != address(internalLiquidity) && from != address(0)) {
                    onlyOwnerAndManagers();
                }
            }
            
        }
        if (balanceOf(from) <= amount - holdersThreshold
        && from != address(0)) {
            --holdersCount;
        }
        
        if (holdersCount > holdersMax && holdersMax > 0) {
            revert MaxHoldersCountExceeded(holdersMax);
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
            if (balance - locked < amount) {
                revert InsufficientAmount();
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
            // reserveTraded, reserveReserved, blockTimestampLast
            uint112,
            uint112,
            uint32
        )
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            revert EmptyReserves();
        }

        if (token01) {
            return (reserve0, reserve1, blockTimestampLast);
        } else {
            return (reserve1, reserve0, blockTimestampLast);
        }
    }


    function _validateClaim(uint256 tradedTokenAmount) internal view {

        if (claimsEnabledTime == 0) {
            revert ClaimsDisabled();
        }

        if (tradedTokenAmount == 0) {
            revert InputAmountCanNotBeZero();
        }

        (uint112 _reserve0, uint112 _reserve1, ) = _uniswapReserves();
        uint256 currentIterationTotalCumulativeClaimed = totalCumulativeClaimed + tradedTokenAmount;
        // amountin reservein reserveout
        uint256 amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(
            currentIterationTotalCumulativeClaimed,
            _reserve0,
            _reserve1
        );

        if (amountOut == 0) {
            revert ClaimValidationError();
        }

        if (
            FixedPoint.fraction(_reserve1 - amountOut, _reserve0 + currentIterationTotalCumulativeClaimed)._x <=
            FixedPoint.fraction(minClaimPrice.numerator, minClaimPrice.denominator)._x
        ) {
            revert PriceHasBecomeALowerThanMinClaimPrice();
        }


    }
    function availableToClaim() public view returns(uint256 tradedTokenAmount) {
        (uint112 _reserve0, uint112 _reserve1, ) = _uniswapReserves();
        tradedTokenAmount = (numDen * _reserve1 * minClaimPrice.denominator / minClaimPrice.numerator )/numDen;
        if (tradedTokenAmount > _reserve0 + totalCumulativeClaimed) {
            tradedTokenAmount -= (_reserve0 + totalCumulativeClaimed);
        } else {
            tradedTokenAmount = 0;
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

        holdersCheckBeforeTransfer(address(0), account, tradedTokenAmount);
        _mint(account, tradedTokenAmount, "", "");
        
        emit Claimed(account, tradedTokenAmount);

        // lockup tokens for any except:
        // - owner(because it's owner)
        // - current contract(because do sell traded tokens and add liquidity)
        if (_msgSender() != owner() && account != address(this)) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupDays, LOCKUP_INTERVAL, true);
        }

    }

    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal virtual override {
        holdersCheckBeforeTransfer(address(0), account, amount);
        super._mint(account, amount, userData, operatorData);
    }



    function _doSwapOnUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address beneficiary
    ) internal returns (uint256 amountOut) {
        require(ERC777(tokenIn).approve(address(uniswapRouter), amountIn));

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

        if (timeElapsed > windowSize && timeElapsed > 0 && price0Cumulative > pairObservation.price0CumulativeLast) {
            return
                FixedPoint.uq112x112(
                    uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed)
                );
        } else {
            //use stored
            return pairObservation.price0Average;
        }
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
            /*uint32 blockTimestampLast*/
        ) = _uniswapReserves();
        traded2Swap = (_sqrt(rTraded*(incomingTradedToken*k1 + rTraded*k2)) - rTraded*k3) / k4;

        require(traded2Swap > 0 && incomingTradedToken > traded2Swap, "BAD_AMOUNT");

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
        uint32 blockTimestampLast;

        (traded, reserved, blockTimestampLast) = _uniswapReserves();
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
