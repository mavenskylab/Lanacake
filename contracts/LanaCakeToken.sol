// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./pancake-swap/interfaces/IPancakeRouter02.sol";
import "./pancake-swap/interfaces/IPancakeFactory.sol";
import "./LanaCakeDividendTracker.sol";
import "./math/SafeMath.sol";
import "./utils/Address.sol";

contract LanaCakeToken is BEP20 {
    using SafeMath for uint256;
    using Address for address;

    uint256 private toMint = 10000000 * 10**18;

    IPancakeRouter02 public pancakeRouter02;
    address public immutable pancakePair;

    // WETH mainnet
    //address public _dividendToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    //WETH testnet
    address public _dividendToken = 0xD3a7Ed22A8b5884C3035A2026424f48c34b8E824;

    address public immutable deadAddress =
        0x000000000000000000000000000000000000dEaD;

    bool private swapping;
    bool public tradingIsEnabled = false;
    bool public buyBackEnabled = false;
    bool public buyBackRandomEnabled = true;

    LanaCakeDividendTracker public dividendTracker;

    address public buyBackWallet = 0xfe6A5fd0cc4d070B3d9c08310814791b61a1631c; // Need to change

    uint256 public maxBuyTranscationAmount = toMint;
    uint256 public maxSellTransactionAmount = toMint;
    uint256 public swapTokensAtAmount = toMint / 100;
    uint256 public maxWalletToken = toMint;

    uint256 public dividendRewardsFee;
    uint256 public marketingFee;
    uint256 public immutable totalFees;

    // sells have fees of 12 and 6 (10 * 1.2 and 5 * 1.2)
    uint256 public sellFeeIncreaseFactor = 130;

    uint256 public marketingDivisor = 30;

    uint256 public _buyBackMultiplier = 100;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

    address public presaleAddress = address(0);

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxSellTFransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) _blacklist;

    event BlacklistUpdated(address indexed user, bool value);
    event UpdateDividendTracker(
        address indexed newAddress,
        address indexed oldAddress
    );

    event UpdatePancakeRouter02(
        address indexed newAddress,
        address indexed oldAddress
    );

    event BuyBackEnabledUpdated(bool enabled);
    event BuyBackRandomEnabledUpdated(bool enabled);
    event SwapAndLiquifyEnabledUpdated(bool enabled);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event ExcludedMaxSellTransactionAmount(
        address indexed account,
        bool isExcluded
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event BuyBackWalletUpdated(
        address indexed newLiquidityWallet,
        address indexed oldLiquidityWallet
    );

    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 bnbReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(uint256 tokensSwapped, uint256 amount);

    event SwapETHForTokens(uint256 amountIn, address[] path);

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() BEP20("LanaCake", "LANA") {
        uint256 _dividendRewardsFee = 8;
        uint256 _marketingFee = 4;

        dividendRewardsFee = _dividendRewardsFee;
        marketingFee = _marketingFee;
        totalFees = _dividendRewardsFee.add(_marketingFee);

        dividendTracker = new LanaCakeDividendTracker();

        buyBackWallet = 0x10792451bedB657E4edE615C635080f3781F3952;

        // Mainnet
        // IPancakeRouter02 _pancakeRouter02 = IPancakeRouter02(
        //     0x10ED43C718714eb63d5aA57B78B54704E256024E
        // );
        // Testnet
        IPancakeRouter02 _pancakeRouter02 = IPancakeRouter02(
            0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
        );

        // Create a pancake swap pair for this new token
        address _pancakePair = IPancakeFactory(_pancakeRouter02.factory())
            .createPair(address(this), _pancakeRouter02.WETH());

        pancakeRouter02 = _pancakeRouter02;
        pancakePair = _pancakePair;

        _setAutomatedMarketMakerPair(_pancakePair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(address(_pancakeRouter02));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(buyBackWallet, true);
        excludeFromFees(address(this), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), toMint);
    }

    receive() external payable {}

    function whitelistDxSale(address _presaleAddress, address _routerAddress)
        public
        onlyOwner
    {
        presaleAddress = _presaleAddress;
        dividendTracker.excludeFromDividends(_presaleAddress);
        excludeFromFees(_presaleAddress, true);

        dividendTracker.excludeFromDividends(_routerAddress);
        excludeFromFees(_routerAddress, true);
    }

    function setMaxBuyTransaction(uint256 maxTxn) external onlyOwner {
        maxBuyTranscationAmount = maxTxn * (10**18);
    }

    function setMaxSellTransaction(uint256 maxTxn) external onlyOwner {
        maxSellTransactionAmount = maxTxn * (10**18);
    }

    function setMaxWalletToken(uint256 maxTxn) external onlyOwner {
        maxWalletToken = maxTxn * (10**18);
    }

    function setSellTransactionMultiplier(uint256 multiplier)
        external
        onlyOwner
    {
        require(
            sellFeeIncreaseFactor >= 100 && sellFeeIncreaseFactor <= 200,
            "LanaCake: Sell transaction multipler must be between 100 (1x) and 200 (2x)"
        );
        sellFeeIncreaseFactor = multiplier;
    }

    function setMarketingDivisor(uint256 divisor) external onlyOwner {
        require(
            marketingDivisor >= 0 && marketingDivisor <= 100,
            "LanaCake: Marketing divisor must be between 0 (0%) and 100 (100%)"
        );
        sellFeeIncreaseFactor = divisor;
    }

    function prepareForPreSale() external onlyOwner {
        setTradingIsEnabled(false);
        dividendRewardsFee = 0;
        marketingFee = 0;
        maxBuyTranscationAmount = totalSupply();
        maxWalletToken = totalSupply();
    }

    function afterPreSale() external onlyOwner {
        dividendRewardsFee = 8;
        marketingFee = 4;
        maxBuyTranscationAmount = totalSupply();
        maxWalletToken = totalSupply();
    }

    function setTradingIsEnabled(bool _enabled) public onlyOwner {
        tradingIsEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function setBuyBackEnabled(bool _enabled) public onlyOwner {
        buyBackEnabled = _enabled;
        emit BuyBackEnabledUpdated(_enabled);
    }

    function setBuyBackRandomEnabled(bool _enabled) public onlyOwner {
        buyBackRandomEnabled = _enabled;
        emit BuyBackRandomEnabledUpdated(_enabled);
    }

    function triggerBuyBack(uint256 amount) public onlyOwner {
        require(
            !swapping,
            "LanaCake: A swapping process is currently running, wait till that is complete"
        );

        uint256 buyBackBalance = address(this).balance;
        swapBNBForTokens(buyBackBalance.div(10**2).mul(amount));
    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(
            newAddress != address(dividendTracker),
            "LanaCake: The dividend tracker already has that address"
        );

        LanaCakeDividendTracker newDividendTracker = LanaCakeDividendTracker(
                payable(newAddress)
            );

        require(
            newDividendTracker.owner() == address(this),
            "LanaCake: The new dividend tracker must be owned by the token contract"
        );

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(address(pancakeRouter02));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateDividendRewardFee(uint8 newFee) public onlyOwner {
        require(
            newFee >= 0 && newFee <= 10,
            "LanaCake: Dividend reward tax must be between 0 and 10"
        );
        dividendRewardsFee = newFee;
    }

    function updateMarketingFee(uint8 newFee) public onlyOwner {
        require(
            newFee >= 0 && newFee <= 10,
            "LanaCake: Dividend reward tax must be between 0 and 10"
        );
        marketingFee = newFee;
    }

    function updatePancakeRouter02(address newAddress) public onlyOwner {
        require(
            newAddress != address(pancakeRouter02),
            "LanaCake: The router already has that address"
        );
        emit UpdatePancakeRouter02(newAddress, address(pancakeRouter02));
        pancakeRouter02 = IPancakeRouter02(newAddress);
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(
            _isExcludedFromFees[account] != excluded,
            "LanaCake: Account is already the value of 'excluded'"
        );
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
        require(
            pair != pancakePair,
            "LanaCake: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "LanaCake: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateBuyBackWallet(address newBuyBackWallet) public onlyOwner {
        require(
            newBuyBackWallet != buyBackWallet,
            "LanaCake: The liquidity wallet is already this address"
        );
        excludeFromFees(newBuyBackWallet, true);
        buyBackWallet = newBuyBackWallet;
        emit BuyBackWalletUpdated(newBuyBackWallet, buyBackWallet);
    }

    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "LanaCake: gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "LanaCake: Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account)
        public
        view
        returns (uint256)
    {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account)
        public
        view
        returns (uint256)
    {
        return dividendTracker.balanceOf(account);
    }

    function getAccountDividendsInfo(address account)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function rand() public view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                        block.difficulty +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (block.timestamp)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (block.timestamp)) +
                        block.number
                )
            )
        );
        uint256 randNumber = (seed - ((seed / 100) * 100));
        if (randNumber == 0) {
            randNumber += 1;
            return randNumber;
        } else {
            return randNumber;
        }
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function isBlackListed(address user) public view returns (bool) {
        return _blacklist[user];
    }

    function blacklistUpdate(address user, bool value)
        public
        virtual
        onlyOwner
    {
        // require(_owner == _msgSender(), "Only owner is allowed to modify blacklist.");
        _blacklist[user] = value;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(
            !isBlackListed(to),
            "Token transfer refused. Receiver is on blacklist"
        );
        super._beforeTokenTransfer(from, to, amount);
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (tradingIsEnabled && automatedMarketMakerPairs[from]) {
            require(
                amount <= maxBuyTranscationAmount,
                "Transfer amount exceeds the maxTxAmount."
            );

            uint256 contractBalanceRecepient = balanceOf(to);
            require(
                contractBalanceRecepient + amount <= maxWalletToken,
                "Exceeds maximum wallet token amount."
            );
        } else if (tradingIsEnabled && automatedMarketMakerPairs[to]) {
            require(
                amount <= maxSellTransactionAmount,
                "Sell transfer amount exceeds the maxSellTransactionAmount."
            );

            uint256 contractTokenBalance = balanceOf(address(this));
            bool canSwap = contractTokenBalance >= swapTokensAtAmount;

            if (!swapping && canSwap) {
                swapping = true;

                uint256 swapTokens = contractTokenBalance.mul(marketingFee).div(
                    totalFees
                );
                swapTokensForBNB(swapTokens);
                transferToBuyBackWallet(
                    payable(buyBackWallet),
                    address(this).balance.div(10**2).mul(marketingDivisor)
                );

                uint256 buyBackBalance = address(this).balance;
                if (buyBackEnabled && buyBackBalance > uint256(1 * 10 * 18)) {
                    swapBNBForTokens(buyBackBalance.div(10**2).mul(rand()));
                }

                if (_dividendToken == pancakeRouter02.WETH()) {
                    uint256 sellTokens = balanceOf(address(this));
                    swapAndSendDividendsInBNB(sellTokens);
                } else {
                    uint256 sellTokens = balanceOf(address(this));
                    swapAndSendDividends(sellTokens);
                }

                swapping = false;
            }
        }

        bool takeFee = tradingIsEnabled && !swapping;

        if (takeFee) {
            uint256 fees = amount.div(100).mul(totalFees);

            // if sell, multiply by 1.2
            if (automatedMarketMakerPairs[to]) {
                fees = fees.div(100).mul(sellFeeIncreaseFactor);
            }

            amount = amount.sub(fees);

            super._transfer(from, address(this), fees);
        }

        super._transfer(from, to, amount);

        try
            dividendTracker.setBalance(payable(from), balanceOf(from))
        {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if (!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gas,
                    tx.origin
                );
            } catch {}
        }
    }

    function swapTokensForBNB(uint256 tokenAmount) private {
        // generate the pancake swap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter02.WETH();

        _approve(address(this), address(pancakeRouter02), tokenAmount);

        // make the swap
        pancakeRouter02.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBNBForTokens(uint256 amount) private {
        // generate the pancake swap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = pancakeRouter02.WETH();
        path[1] = address(this);

        // make the swap
        pancakeRouter02.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amount
        }(
            0, // accept any amount of Tokens
            path,
            deadAddress, // Burn address
            block.timestamp.add(300)
        );

        emit SwapETHForTokens(amount, path);
    }

    function swapTokensForDividendToken(uint256 tokenAmount, address recipient)
        private
    {
        // generate the pancake swap pair path of weth -> busd
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = pancakeRouter02.WETH();
        path[2] = _dividendToken;

        _approve(address(this), address(pancakeRouter02), tokenAmount);

        // make the swap
        pancakeRouter02.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of dividend token
            path,
            recipient,
            block.timestamp
        );
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForDividendToken(tokens, address(this));
        uint256 dividends = IBEP20(_dividendToken).balanceOf(address(this));
        bool success = IBEP20(_dividendToken).transfer(
            address(dividendTracker),
            dividends
        );

        if (success) {
            dividendTracker.distributeDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }

    function swapAndSendDividendsInBNB(uint256 tokens) private {
        uint256 currentBNBBalance = address(this).balance;
        swapTokensForBNB(tokens);
        uint256 newBNBBalance = address(this).balance;

        uint256 dividends = newBNBBalance.sub(currentBNBBalance);
        (bool success, ) = address(dividendTracker).call{value: dividends}("");

        if (success) {
            dividendTracker.distributeDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }

    function transferToBuyBackWallet(address payable recipient, uint256 amount)
        private
    {
        recipient.transfer(amount);
    }
}
