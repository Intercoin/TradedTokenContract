// SPDX-License-Identifier: AGPL
pragma solidity >= 0.8.0 < 0.9.0;

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
    
    // struct ClaimSettings {
    //     PriceNumDen minClaimPrice;
    //     PriceNumDen minClaimPriceGrow;
    // }

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

    struct BuyInfo {
        address token;
        uint256 price;
    }

    struct MaxVars {
        uint16 buyTaxMax;
        uint16 sellTaxMax;
        uint16 holdersMax;
        uint256 maxTotalSupply;
    }
    
    RateLimit public panicSellRateLimit;

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

    //PriceNumDen minClaimPrice;
    //uint64 internal lastMinClaimPriceUpdatedTime;
    //PriceNumDen minClaimPriceGrow;

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

    uint256 public cumulativeClaimed;

    uint256 public maxTotalSupply;

    address public buyToken;
    uint256 public buyPrice;

    uint256 allTimeHighGrowthFraction;
    FixedPoint.uq112x112 allTimeHighPriceAverageData;
    FixedPoint.uq112x112 allTimeHighPriceAverageDataPrev;

    Liquidity internal internalLiquidity;
    Observation internal pairObservation;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    mapping(address => uint64) public managers;
    mapping(address => uint64) public presales;
    mapping(address => uint64) public sales;

    bool private addedInitialLiquidityRun;

    event AddedInitialLiquidity(uint256 tradedTokenAmount, uint256 reserveTokenAmount);
    event AddedLiquidity(uint256 tradedTokenAmount, uint256 priceAverageData);
    event AddedManager(address account, address sender);
    event Claimed(address account, uint256 amount);
    event ClaimsEnabled(uint64 claimsEnabledTime);
    event IncreasedHoldersMax(uint16 newHoldersMax);
    event IncreasedHoldersThreshold(uint256 newHoldersThreshold);
    event PanicSellRateExceeded(address indexed holder, address indexed recipient, uint256 amount);
    event Presale(address account, uint256 amount);
    event PresaleTokensBurned(address account, uint256 burnedAmount);
    event RemovedManager(address account, address sender);
    event Sale(address saleContract, uint64 lockupDays);
    event UpdatedTaxes(uint256 sellTax, uint256 buyTax);

    error AlreadyCalled();
    error BeforeInitialLiquidityRequired();
    error BuyNotAvailable();
    error CantCreatePair(address tradedToken, address reserveToken);
    error ClaimsEnabledTimeAlreadySetup();
    error ClaimsDisabled();
    error ClaimValidationError();
    error EmptyAccountAddress();
    error EmptyAddress();
    error EmptyManagerAddress();
    error EmptyReserves();
    error InitialLiquidityRequired();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();
    error InvalidSellRateLimitFraction();
    error ManagersOnly();
    error MaxHoldersCountExceeded(uint256 count);
    error MaxTotalSupplyExceeded();
    //error MinClaimPriceGrowTooFast();
    error OwnerAndManagersOnly();
    error OwnersOnly();
    error PriceDropTooBig();
    //error PriceHasBecomeALowerThanMinClaimPrice();
    error TaxesTooHigh();
    error ReserveTokenInvalid();
    //error ShouldBeMoreThanMinClaimPrice();
    error ZeroDenominator();

    /**
     * @param tokenName_ token name
     * @param tokenSymbol_ token symbol
     * @param reserveToken_ reserve token address
     * @param priceDrop_ price drop while add liquidity
     * @param lockupDays_ interval amount in days (see minimum lib)
     * @param panicSellRateLimit_ (fraction, duration) if fraction != 0, can sell at most this fraction of balance per interval with this duration
     * @param maxVars struct with maximum vars for several variables
     *  param buyTaxMax buyTaxMax_
     *  param sellTaxMax sellTaxMax_
     *  param holdersMax the maximum number of holders, may be increased by owner later
     *  param maxTotalSupply the maximum totalSupply can be minted,  if 0 - unlimited
     * @param buyInfo struct with token and price
     *  param token token's address 
     *  param price buy price
     */
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupDays_,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        MaxVars memory maxVars,
        BuyInfo memory buyInfo
        
    ) ERC777(tokenName_, tokenSymbol_, new address[](0)) {

        //setup
        (buyTaxMax,  sellTaxMax,  holdersMax, maxTotalSupply) =
        (maxVars.buyTaxMax, maxVars.sellTaxMax, maxVars.holdersMax, maxVars.maxTotalSupply);

        buyToken = buyInfo.token;
        buyPrice = buyInfo.price;

        tradedToken = address(this);
        reserveToken = reserveToken_;

        startupTimestamp = _currentBlockTimestamp();
        pairObservation.timestampLast = _currentBlockTimestamp();
        
        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory, k1, k2, k3, k4) = SwapSettingsLib.netWorkSettings();

        priceDrop = priceDrop_;
        lockupDays = lockupDays_;
        
        panicSellRateLimit.duration = panicSellRateLimit_.duration;
        panicSellRateLimit.fraction = panicSellRateLimit_.fraction;

        taxesInfo.init(taxesInfoInit);

        if (reserveToken == address(0)) {
            revert ReserveTokenInvalid();
        }

        if (reserveToken_ == address(0)) {
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
        
        _validateClaim(tradedTokenAmount, account);
        _claim(tradedTokenAmount, account);

        _update();
    }

    /**
    * @notice enable "claim mode". After calling, it is possible to invoke the claim() function
    */
    function enableClaims() external onlyOwner {
        if (claimsEnabledTime != 0) {
            revert ClaimsEnabledTimeAlreadySetup();
        }
        claimsEnabledTime = uint64(block.timestamp);
        emit ClaimsEnabled(claimsEnabledTime);
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

        uint256 traded2Swap;
        uint256 traded2Liq;
        uint256 priceAverageData; // it's fixed point uint224

        uint112 traded;
        uint112 reserved;

        (traded, reserved,/* blockTimestampLast*/) = _uniswapReserves();

        //-------------
        bool err;
        (
            err,
            tradedTokenAmount,
            traded2Swap,
            traded2Liq,
            priceAverageData
        ) = _validatePriceDrop(traded, reserved, tradedTokenAmount);
        if (err) {
            revert PriceDropTooBig();
        }

        // trade trade tokens and add liquidity
        _doSellTradedAndLiquidity(traded2Swap, traded2Liq);
        // emit event
        emit AddedLiquidity(tradedTokenAmount, priceAverageData);
        // update pricaAverage
        _update();
    }

    /**
    * @notice thw way to buy Traded token. ofc if defined buyPrice in constructor method
    * @param amount the amount to buy
    */
    function buy(uint256 amount) external payable {

        if (buyPrice == 0) {
            revert BuyNotAvailable();
        }

        if (buyToken == address(0)) {
            amount = msg.value;
        } else {
            IERC20(buyToken).transferFrom(msg.sender, address(this), amount);
        }
        uint256 amountToMint = amount / buyPrice;
        if (amountToMint == 0) {
            revert BuyNotAvailable();
        }
        _mint(msg.sender, amountToMint, "", "");

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
    function transferFrom(address holder, address recipient, uint256 amount) public virtual override returns (bool) {
        amount = _handleTransferToUniswap(holder, recipient, amount);
        return super.transferFrom(holder, recipient, amount);
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
     * @param presaleLockupDays the number of days people who obtained the token in the presale cannot transfer tokens for
     */
    function startPresale(address contract_, uint256 amount, uint64 presaleLockupDays) public onlyOwner {
        onlyBeforeInitialLiquidity();
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

    /**
    * @notice returns the locked amount for the "from" account
    * @param from address
    */
    function getLockedAmount(address from) public view returns(uint256) {
        return tokensLocked[from]._getMinimum();
    }

    /**
    * @notice returns the maximum available amount
    */
    function availableToClaim() public view returns(uint256 tradedTokenAmount) {
        return _availableToClaim(0); // try to get maximum as possible
    }

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
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
    * @notice Answers the question of "how many tokens can be mined such that the "new_current_price" is not higher than "average_price(1-price_drop)""
    */
    function _validatePriceDrop(
        uint112 traded,
        uint112 reserved,
        uint256 tradedTokenAmount
    ) 
        internal 
        view
        returns(
            bool err,                       // true - if cant exchange or priceDrop too big
            uint256 tradedTokenAmountRet,   // if tradedTokenAmount == 0then return maximum as possible, overwise - tradedTokenAmount == tradedTokenAmountRet
            uint256 traded2Swap,            // what's part need to swap from tradedTokenAmount to reserveToken to add liquidity without tradedToken remainder
            uint256 traded2Liq,             // parts without traded2Swap to add liquidity without tradedToken remainder
            uint256 priceAverageData // it's fixed point uint224
        )
    {
        uint256 reserved2Liq;
        uint256 rTraded;
        uint256 rReserved;
        
        uint256 tradedReserve1;
        uint256 tradedReserve2;

        (tradedReserve1, tradedReserve2, priceAverageData) = _maxAddLiquidity(traded, reserved);

        if (tradedReserve1 < tradedReserve2 && tradedTokenAmount <= (tradedReserve2 - tradedReserve1)) {
            //err = false;
            
            // if tradedTokenAmount is zero, let's use the maximum amount of traded tokens allowed
            if (tradedTokenAmount == 0) {
                tradedTokenAmountRet = tradedReserve2 - tradedReserve1;
            } else {
                tradedTokenAmountRet = tradedTokenAmount;
            }

            (rTraded, rReserved, traded2Swap, traded2Liq, reserved2Liq) = _calculateSellTradedAndLiquidity(
                tradedTokenAmountRet
            );

            FixedPoint.uq112x112 memory averageWithPriceDrop = (
                FixedPoint.muluq(
                    FixedPoint.uq112x112(uint224(priceAverageData)),
                    FixedPoint.muluq(
                        FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)),
                        FixedPoint.fraction(1, FRACTION)
                    )   
                )
                    
            );
//console.log("_validatePriceDrop:averageWithPriceDrop =", averageWithPriceDrop._x);
            // "new_current_price" should be more than "average_price(1-price_drop)"
            if (
                FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x <=
                averageWithPriceDrop._x
            ) {
// console.log("_validatePriceDrop:err(0)=",true);
// console.log("_validatePriceDrop:traded2Swap=",traded2Swap);
// console.log("_validatePriceDrop:traded2Liq=",traded2Liq);
// console.log("_validatePriceDrop:tradedTokenAmount=",tradedTokenAmount);
// console.log("_validatePriceDrop:tradedTokenAmountRet=",tradedTokenAmountRet);
// console.log("_validatePriceDrop:rReserved / (rTraded + traded2Swap + traded2Liq))._x=",FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x);
// console.log("_validatePriceDrop:rReserved / rTraded)._x                             =",FixedPoint.fraction(rReserved, rTraded)._x);
// console.log("_validatePriceDrop:priceAverageData._x                                 =",priceAverageData);
// console.log("_validatePriceDrop:averageWithPriceDrop._x                             =",averageWithPriceDrop._x);

                err = true;
            }
        } else {
// console.log("_validatePriceDrop:err(1)=",true);
            err = true;
        }
    }

    /**
    * @notice validate claim for `tradedTokenAmount`
    * @param tradedTokenAmount tradedToken amount
    */
    function _validateClaim(uint256 tradedTokenAmount, address account) internal view {

        if (claimsEnabledTime == 0) {
            revert ClaimsDisabled();
        }

        if (tradedTokenAmount == 0) {
            revert InputAmountCanNotBeZero();
        }
        
        if (account == address(0)) {
            revert EmptyAccountAddress();
        }

        uint256 amountOut = availableToClaim();

        if (amountOut == 0 || amountOut < tradedTokenAmount) {
            revert ClaimValidationError();
        }
    }

    /**
    * @notice it's hook which preventing panic from users and limit tokens to sell. 
    *  only `current balance * panicSellRateLimit.fraction` available to sell in `panicSellRateLimit.duration`
    * @param holder holder's address
    * @param recipient recipient's address
    * @param amount traded token's amount
    * @return adjustedAmount adjusted traded token's amount
    */
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

    /**
    * @notice another hook that updates the holders count (only if it exceeds holdersThreshold) and limit holdersMax
    *  A user becomes a holder if they obtain tokens, and this amount exceeds the holdersThreshold."
    * @param from from's address
    * @param to to's address
    * @param amount traded token's amount
    */
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

    /**
    * @notice either owner or managers
    */
    function onlyOwnerAndManagers() internal view {
        if (owner() != _msgSender() && managers[_msgSender()] == 0) {
            revert OwnerAndManagersOnly();
        }
    }

    /**
    * @notice only managers without owner
    function onlyManagers() internal view {
        if (managers[_msgSender()] == 0) {
            revert ManagersOnly();
        }
    }

    /**
    * @notice can only add liquidity once
    */
    function addLiquidityOnlyOnce() internal {
        if (addedInitialLiquidityRun) {
            revert AlreadyCalled();
        }
        addedInitialLiquidityRun = true;
    }

    /**
    * @notice after initial liquidity was added
    */
    function initialLiquidityRequired() internal view {
        if (!addedInitialLiquidityRun) {
            revert InitialLiquidityRequired();
        }
    }

    /**
    * @notice before initial liquidity was added
    */
    function onlyBeforeInitialLiquidity() internal view{
        if (addedInitialLiquidityRun) {
            revert BeforeInitialLiquidityRequired();
        }
    }

    /**
    @notice called before any transfer. Checks holders count and locked tokens
        Reverted if insufficient amount
    */
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

    function _availableToClaim(uint256 tradedTokenAmount) internal view returns(uint256 tradedTokenAmountRet) {
        (uint112 _reserve0, uint112 _reserve1, ) = _uniswapReserves();
        bool err;

        (err,tradedTokenAmountRet,,,) = _validatePriceDrop(_reserve0, _reserve1, tradedTokenAmount);
//console.log("_availableToClaim:err =", err);
        if (err) {
            tradedTokenAmountRet = 0;
        } else {
//console.log("_availableToClaim:tradedTokenAmountRet =", tradedTokenAmountRet);
            uint256 currentIterationTotalCumulativeClaimed = cumulativeClaimed + tradedTokenAmountRet;
            // amountin reservein reserveout
            uint256 reservedTokenAmount = IUniswapV2Router02(uniswapRouter).getAmountOut(
                currentIterationTotalCumulativeClaimed,
                _reserve0,
                _reserve1
            );
            if (reservedTokenAmount == 0) {
                tradedTokenAmountRet = 0;
            }
        }
    }

    /**
     * @notice do claim to the `account` and locked tokens if
     */
    function _claim(uint256 tradedTokenAmount, address account) internal {
        
        cumulativeClaimed += tradedTokenAmount;

        _mint(account, tradedTokenAmount, "", "");
        
        emit Claimed(account, tradedTokenAmount);

        // _handleTransferToUniswap tokens for any except:
        // - owner(because it's owner)
        // - current contract(because do sell traded tokens and add liquidity)
        if (_msgSender() != owner() && account != address(this)) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupDays, LOCKUP_INTERVAL, true);
        }

    }

    /**
    * @notice hook handles transfers on uniswap.
    *   and if uniswap - 
    *   - prevents transfers on uniswap before added initial liquidity
    *   - initiate prevent panic mechanism
    *   - burn selltaxes 
    * @param holder holder
    * @param recipient recipient
    * @param amount amount
    */
    function _handleTransferToUniswap(address holder, address recipient, uint256 amount) internal returns(uint256) {
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
            } catch Error(string memory/* _err*/) {
                // do nothing
            } catch (bytes memory /*_err*/) {
                // do nothing
            }
        }
        return amount;
    }

    /**
    * @notice Overridden mint with additional checks to prevent exceeding maxTotalSupply.
    */
    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal virtual override {
        if (maxTotalSupply > 0 && totalSupply()+amount > maxTotalSupply) {
            revert MaxTotalSupplyExceeded();
        }
        super._mint(account, amount, userData, operatorData);
    }

    /**
    * @notice simple swap tokenIn into tokenOut 
    */
    function _doSwapOnUniswap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address beneficiary
    ) internal returns (uint256 amountOut) {
        require(ERC777(tokenIn).approve(address(uniswapRouter), amountIn), "NEEDS_APPROVAL");

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

    /**
    * @notice returns current(means in window size) price0Average 
    *   traded average price is average from two priceCumulativeLast values
    */
    function _tradedAveragePrice(

    ) 
        internal 
        view 
        returns (
            bool isNeedUpdate,
            FixedPoint.uq112x112 memory price0Average,
            uint256 price0Cumulative,
            uint64 blockTimestamp
        ) 
    {
        blockTimestamp = _currentBlockTimestamp();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
        
        uint64 windowSize = ((blockTimestamp - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();

        if (timeElapsed > windowSize && timeElapsed > 0 && price0Cumulative > pairObservation.price0CumulativeLast) {
            isNeedUpdate = true;
            price0Average = FixedPoint.divuq(
                FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast)),
                FixedPoint.encode(timeElapsed)
            );
        } else {
            isNeedUpdate = false;
            //use stored
            price0Average = pairObservation.price0Average;
        }
    }

    /**
    * @notice updates price0Average. method called in every `claim` and `addLiquidity` methods
    */
    function _update() internal {
        bool isNeedUpdate;
        FixedPoint.uq112x112 memory price0Average;
        uint256 price0Cumulative;
        uint64 blockTimestamp;

        (isNeedUpdate, price0Average, price0Cumulative, blockTimestamp) = _tradedAveragePrice();
        if (isNeedUpdate) {
            pairObservation.price0Average = price0Average;
            pairObservation.price0CumulativeLast = price0Cumulative;
            pairObservation.timestampLast = blockTimestamp;

            // alltimehigh check
            FixedPoint.uq112x112 memory allTimeHigh = FixedPoint.muluq(
                allTimeHighPriceAverageData,
                FixedPoint.divuq(
                    FixedPoint.encode(uint112(allTimeHighGrowthFraction) + uint112(FRACTION)),
                    FixedPoint.encode(uint112(FRACTION))
                )
            );
            if (price0Average._x> allTimeHigh._x) {
                cumulativeClaimed = 0;
                allTimeHighPriceAverageDataPrev = allTimeHighPriceAverageData;
                allTimeHighPriceAverageData = price0Average;
            }
        }
        
        

    }

    /**
    * @notice Calculate which parts of the traded tokens need to be swapped into reserves to add liquidity without leaving remaining traded tokens or reserved tokens.
    *   traded2Swap = (_sqrt(rTraded*(incomingTradedToken*k1 + rTraded*k2)) - rTraded*k3) / k4;
    *   WHERE  k1,k2,k3,k4 - see koefficients in SwapSettingsLib   
    */
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

    /**
    * @notice internal method to sell traded tokens and add liquidity 
    */
    function _doSellTradedAndLiquidity(uint256 traded2Swap, uint256 traded2Liq) internal {
        // claim to address(this) necessary amount to swap from traded to reserved tokens
        _mint(address(this), traded2Swap, "", "");
        _doSwapOnUniswap(tradedToken, reserveToken, traded2Swap, address(internalLiquidity));

        // mint that left to  internalLiquidity contract
        _mint(address(internalLiquidity), traded2Liq, "", "");

        // add to liquidity from there
        internalLiquidity.addLiquidity();
    }

    /**
    * @notice calculate price average data and difference of reserves tradedtokens before and after drop price
    */
    function _maxAddLiquidity(
        uint112 traded,
        uint112 reserved
    )
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
        FixedPoint.uq112x112 memory priceAverage;
        (,priceAverage,,) = _tradedAveragePrice();

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
                                priceAverage,
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

        return (traded, tradedNew, priceAverage._x);
    }

    /**
    @notice Calculate the square root
    */
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
