// SPDX-License-Identifier: AGPL
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";
import "./minimums/libs/MinimumsLib.sol";
import "./helpers/Liquidity.sol";

//import "hardhat/console.sol";

contract TradedToken is Ownable, IERC777Recipient, IERC777Sender, ERC777, ReentrancyGuard {
    using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    using SafeERC20 for ERC777;

    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }

    struct Observation {
        uint64 timestampLast;
        uint256 price0CumulativeLast;
        FixedPoint.uq112x112 price0Average;
    }

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    
    uint64 public claimsEnabledTime;
    
    /**
     * @custom:shortd claimFrequency
     * @notice claimFrequency
     */
    uint16 public immutable claimFrequency;
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

    /**
     * @custom:shortd external token
     * @notice external token
     */
    address public immutable claimingToken;
    PriceNumDen claimingTokenExchangePrice;

    /**
     * @custom:shortd uniswap v2 pair
     * @notice uniswap v2 pair
     */
    address public immutable uniswapV2Pair;

    address internal uniswapRouter;
    address internal uniswapRouterFactory;

    // keep gas when try to get reserves
    // if token01 == true then (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) so reserve0 it's reserves of TradedToken
    bool internal immutable token01;
    bool internal alreadyRunStartupSync;

    uint64 internal constant AVERAGE_PRICE_WINDOW = 5;
    uint64 internal constant FRACTION = 10000;
    uint64 internal constant LOCKUP_INTERVAL = 1 days; //24 * 60 * 60; // day in seconds
    uint64 internal immutable startupTimestamp;
    uint64 internal immutable lockupIntervalAmount;

    uint64 public immutable buyTaxMax;
    uint64 public immutable sellTaxMax;
    
    uint64 public buyTax;
    uint64 public sellTax;
    uint256 public totalCumulativeClaimed;

    Liquidity internal internalLiquidity;
    Observation internal pairObservation;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    mapping(address => uint64) internal managers;

    mapping(address => uint256) public wantToClaimMap;
    uint256 public wantToClaimTotal; // value that accomulated all users `wantToClaim requests`
    
    bool private addedInitialLiquidityRun;

    event AddedLiquidity(uint256 tradedTokenAmount, uint256 priceAverageData);
    event AddedManager(address account, address sender);
    event AddedInitialLiquidity(uint256 tradedTokenAmount, uint256 reserveTokenAmount);
    event UpdatedTaxes(uint256 sellTax, uint256 buyTax);
    event Claimed(address account, uint256 amount);

    error AlreadyCalled();
    error InitialLiquidityRequired();
    error reserveTokenInvalid();
    error EmptyAddress();
    error EmptyAccountAddress();
    error EmptyManagerAddress();
    error EmptyTokenAddress();
    error CanNotBeZero();
    error InputAmountCanNotBeZero();
    error InsufficientAmount();
    error TaxCanNotBeMoreThen(uint64 fraction);
    error PriceDropTooBig();
    error ManagersOnly();
    error CantCreatePair(address tradedToken, address reserveToken);
    error BuyTaxInvalid();
    error SellTaxInvalid();
    error EmptyReserves();
    error ClaimValidationError();
    error PriceHasBecomeALowerThanMinClaimPrice();
    error ClaimsEnabledTimeAlreadySetup();
    
    modifier onlyManagers() {
        // if (owner() == _msgSender() || managers[_msgSender()] != 0) {
        // } else {
        //     revert ManagersOnly();
        // }
        // lets transform via de'Morgan law
        if (owner() != _msgSender() && managers[_msgSender()] == 0) {
            revert ManagersOnly();
        }

        _;
    }

    modifier runOnlyOnce() {
        if (addedInitialLiquidityRun) {
            revert AlreadyCalled();
        }
        addedInitialLiquidityRun = true;
        _;
    }

    modifier initialLiquidityRequired() {
        if (!addedInitialLiquidityRun) {
            revert InitialLiquidityRequired();
        }
        _;
    }

    /**
     * @param tokenName_ token name
     * @param tokenSymbol_ token symbol
     * @param reserveToken_ reserve token address
     * @param priceDrop_ price drop while add liquidity
     * @param lockupIntervalAmount_ interval amount in days (see minimum lib)
     * @param minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
     * @param claimingToken_ external token address that used to change their tokens to traded
     * @param claimingTokenExchangePrice_ (numerator,denominator) exchange price. used when user trying to change external token to Traded
     * @param buyTaxMax_ buyTaxMax_
     * @param sellTaxMax_ sellTaxMax_
     * @param claimFrequency_ claimFrequency_
     */
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupIntervalAmount_,
        PriceNumDen memory minClaimPrice_,
        address claimingToken_,
        PriceNumDen memory claimingTokenExchangePrice_,
        uint64 buyTaxMax_,
        uint64 sellTaxMax_,
        uint16 claimFrequency_
    ) ERC777(tokenName_, tokenSymbol_, new address[](0)) {
        

        addedInitialLiquidityRun = false;

        buyTaxMax = buyTaxMax_;
        sellTaxMax = sellTaxMax_;
        claimFrequency = claimFrequency_;

        //input validations
        if (reserveToken_ == address(0)) {
            revert reserveTokenInvalid();
        }

        tradedToken = address(this);
        reserveToken = reserveToken_;
        priceDrop = priceDrop_;
        lockupIntervalAmount = lockupIntervalAmount_;

        minClaimPrice.numerator = minClaimPrice_.numerator;
        minClaimPrice.denominator = minClaimPrice_.denominator;
        claimingToken = claimingToken_;
        claimingTokenExchangePrice.numerator = claimingTokenExchangePrice_.numerator;
        claimingTokenExchangePrice.denominator = claimingTokenExchangePrice_.denominator;

        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();

        // check inputs
        if (uniswapRouter == address(0) || uniswapRouterFactory == address(0)) {
            revert EmptyAddress();
        }
        if (
            claimingTokenExchangePrice_.numerator == 0 || 
            claimingTokenExchangePrice_.denominator == 0 || 
            minClaimPrice_.numerator == 0 || 
            minClaimPrice_.denominator == 0
        ) { 
            revert CanNotBeZero();
        }

        if (buyTaxMax_ > FRACTION || sellTaxMax_ > FRACTION) {
            revert TaxCanNotBeMoreThen(FRACTION);
        }
        
        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        //create Pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);

        if (uniswapV2Pair == address(0)) {
            revert CantCreatePair(tradedToken, reserveToken);
        }

        startupTimestamp = _currentBlockTimestamp();
        pairObservation.timestampLast = _currentBlockTimestamp();

        // TypeError: Cannot write to immutable here: Immutable variables cannot be initialized inside an if statement.
        // if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
        //     token01 = true;
        // }
        // but can do if use ternary operator :)
        token01 = (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) ? true : false;

        // IUniswapV2Pair(uniswapV2Pair).sync(); !!!! not created yet

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

    function addManagers(
        address manager
    )
        external
        onlyManagers
    {
        if (manager == address(0)) {revert EmptyManagerAddress();}
        managers[manager] = _currentBlockTimestamp();

        emit AddedManager(manager, _msgSender());
    }
    /**
     * @notice setting buy tax
     * @param fraction buy tax
     * @custom:calledby owner
     */
    function setBuyTax(uint64 fraction) external onlyOwner {
        if (fraction > buyTaxMax) {
            revert TaxCanNotBeMoreThen(buyTaxMax);
        }
        buyTax = fraction;
        emit UpdatedTaxes(sellTax, buyTax);
    }

    /**
     * @notice setting sell tax
     * @param fraction sell tax
     * @custom:calledby owner
     */
    function setSellTax(uint64 fraction) external onlyOwner {
        if (fraction > sellTaxMax) {
            revert TaxCanNotBeMoreThen(sellTaxMax);
        }
        sellTax = fraction;
        emit UpdatedTaxes(sellTax, buyTax);
    }

    /**
     * @dev adding initial liquidity. need to donate `amountReserveToken` of reserveToken into the contract. can be called once
     * @param amountTradedToken amount of traded token which will be claimed into contract and adding as liquidity
     * @param amountReserveToken amount of reserve token which must be donate into contract by user and adding as liquidity
     */
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external onlyOwner runOnlyOnce {
        if (amountTradedToken == 0 || amountReserveToken == 0) {
            revert InputAmountCanNotBeZero();
        }
        if (amountReserveToken > ERC777(reserveToken).balanceOf(address(this))) {
            revert InsufficientAmount();
        }

        _claim(amountTradedToken, address(this));

        ERC777(tradedToken).safeTransfer(address(internalLiquidity), amountTradedToken);
        ERC777(reserveToken).safeTransfer(address(internalLiquidity), amountReserveToken);

        internalLiquidity.addLiquidity();

        emit AddedInitialLiquidity(amountTradedToken, amountReserveToken);
        // singlePairSync() ??

        // console.log("force sync start");

        //force sync
        //IUniswapV2Pair(uniswapV2Pair).sync();

        // // and update
        // _update();
    }

    /**
     * @notice claims `tradedTokenAmount` to caller
     * @param tradedTokenAmount amount of traded token to claim
     * @custom:calledby owner
     */
    function claim(uint256 tradedTokenAmount) external onlyManagers {
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, msg.sender);
    }

    /**
     * @notice claims to account
     * @param tradedTokenAmount amount of traded token to claim
     * @param account address to claim for
     * @custom:calledby owner
     */
    function claim(uint256 tradedTokenAmount, address account)
        external
        onlyManagers
    {
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
    * If there is a claimingToken, then they have to pass an amount that is <= claimingToken.balanceOf(caller). 
    * If they pass zero here, it will actually look up and use their entire balance.
    */
    function wantToClaim(
        uint256 amount
    ) 
        external 
    {
        address sender = _msgSender();
        uint256 availableAmount = ERC777(claimingToken).balanceOf(sender);
        
        if (amount == 0) {
            amount = availableAmount;
        }

        if (availableAmount < amount || amount == 0) {
            revert InsufficientAmount();
        }

        wantToClaimTotal += amount - wantToClaimMap[sender];
        wantToClaimMap[sender] = amount;

    }

    /**
     * @notice claims to account traded tokens instead external tokens(if set). external tokens will send to dead address
     * @param claimingTokenAmount amount of external token to claim traded token
     * @param account address to claim for
     */
    function claimViaExternal(uint256 claimingTokenAmount, address account) external nonReentrant() {
        if (claimingToken == address(0)) { 
            revert EmptyTokenAddress();
        }
        if (claimingTokenAmount == 0) { 
            revert InputAmountCanNotBeZero();
        }
        if (claimingTokenAmount > ERC777(claimingToken).allowance(msg.sender, address(this))) {
            revert InsufficientAmount();
        }
        
        ERC777(claimingToken).safeTransferFrom(msg.sender, DEAD_ADDRESS, claimingTokenAmount);

        uint256 tradedTokenAmount = (claimingTokenAmount * claimingTokenExchangePrice.numerator) /
            claimingTokenExchangePrice.denominator;

        _validateClaim(tradedTokenAmount);

        _claim(tradedTokenAmount, account);
    }

    /**
     * @dev claims, sells, adds liquidity, sends LP to 0x0
     * @custom:calledby owner
     */
    function addLiquidity(uint256 tradedTokenAmount) external onlyManagers initialLiquidityRequired {
        if (tradedTokenAmount == 0) {
            revert CanNotBeZero();
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
                FixedPoint
                    .uq112x112(uint224(priceAverageData))
                    .muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)))
                    .muluq(FixedPoint.fraction(1, FRACTION))
            );

            // "new_current_price" should be more than "average_price(1-price_drop)"
            if (
                FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x <=
                // (
                //     FixedPoint.uq112x112(uint224(priceAverageData)).muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop))).muluq(FixedPoint.fraction(1, FRACTION))
                // )._x
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
    
    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        if(uniswapV2Pair == recipient && holder != address(internalLiquidity)) {
            uint256 taxAmount = (amount * sellTax) / FRACTION;
            if (taxAmount != 0) {
                amount -= taxAmount;
                _burn(holder, taxAmount, "", "");
            }
        }
        return super.transferFrom(holder, recipient, amount);
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        //address from = _msgSender();

        // inject into transfer and burn tax from sender
        // two ways:
        // 1. make calculations, burn taxes from sender and do transaction with substracted values
        if (uniswapV2Pair == _msgSender()) {
            uint256 taxAmount = (amount * buyTax) / FRACTION;

            if (taxAmount != 0) {
                amount -= taxAmount;
                _burn(_msgSender(), taxAmount, "", "");
            }
        }
        return super.transfer(recipient, amount);

        // 2. do usual transaction, then make calculation and burn tax from sides(buyer or seller)
        // we DON'T USE this case, because have callbacks in _move method: _callTokensToSend and _callTokensReceived
        // and than be send to some1 else in recipient contract callback
    }

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    
    function _beforeTokenTransfer(
        address, /*operator*/
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

    /**
    * @notice 
        validate params when user claims
        here we should simulate swap totalCumulativeClaimed to reserve token and check price
        price should be less than minClaimPrice
    */
    function _validateClaim(uint256 tradedTokenAmount) internal view {
        if (tradedTokenAmount == 0) {
            revert CanNotBeZero();
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

        // lockup tokens for any except:
        // - owner(because it's owner)
        // - current contract(because do sell traded tokens and add liquidity)
        if (_msgSender() != owner() && account != address(this)) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupIntervalAmount, LOCKUP_INTERVAL, true);
        }

    }

    //
    /**
     * @notice do swap for internal liquidity contract
     */
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

    /**
     * @notice
     */
    function _tradedAveragePrice() internal view returns (FixedPoint.uq112x112 memory) {
        uint64 blockTimestamp = _currentBlockTimestamp();
        uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
        uint64 windowSize = ((blockTimestamp - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        if (timeElapsed > windowSize && timeElapsed > 0 && price0Cumulative > pairObservation.price0CumulativeLast) {
            // console.log("timeElapsed > windowSize && timeElapsed>0");
            // console.log("price0Cumulative                       =", price0Cumulative);
            // console.log("pairObservation.price0CumulativeLast   =", pairObservation.price0CumulativeLast);
            // console.log("timeElapsed                            =", timeElapsed);
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

            pairObservation.price0Average = FixedPoint
                .uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast))
                .divuq(FixedPoint.encode(timeElapsed));
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

        // inspired by https://blog.alphaventuredao.io/onesideduniswap/
        traded2Swap = (_sqrt(rTraded*(incomingTradedToken*3988000 + rTraded*3988009)) - rTraded*1997) / 1994;

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

        FixedPoint.uq112x112 memory q1 = FixedPoint.encode(uint112(_sqrt(traded)));
        FixedPoint.uq112x112 memory q2 = FixedPoint.encode(uint112(_sqrt(reserved)));
        FixedPoint.uq112x112 memory q3 = (
            priceAverageData.muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop))).muluq(
                FixedPoint.fraction(1, FRACTION)
            )
        ).sqrt();
        //FixedPoint.uq112x112 memory q4 = FixedPoint.encode(uint112(1)).divuq(q3);

        //traded1*reserve1/(priceaverage*pricedrop)

        //traded1 * reserve1*(1/(priceaverage*pricedrop))

        uint256 tradedNew = (
            q1.muluq(q2).muluq(FixedPoint.encode(uint112(_sqrt(FRACTION)))).muluq(
                FixedPoint.encode(uint112(1)).divuq(q3)
            )
        ).decode();

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
