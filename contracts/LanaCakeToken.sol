// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Token/BEP20/BEP20.sol";
import "./access/Ownable.sol";
import "./uniswap/interfaces/IUniswapV2Router02.sol";

contract LanaCakeToken is BEP20, Ownable {
    uint256 public totalSupply = 10000 * 10 ** 18;

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    address public _dividendToken = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public immutable deadAddress = 0x000000000000000000000000000000000000dEaD;

    bool private swapping;
    bool public tradingIsEnabled = false;
    bool public buyBackEnabled = false;
    bool public buyBackRandomEnabled = true;

    address public buyBackWallet = 0x10792451bedB657E4edE615C635080f3781F3952; // Need to change

    uint256 public maxBuyTranscationAmount = totalSupply;
    uint256 public maxSellTransactionAmount = totalSupply;
    uint256 public swapTokensAtAmount = totalSupply / 100000;
    uint256 public maxWalletToken = totalSupply; 

    // sells have fees of 12 and 6 (10 * 1.2 and 5 * 1.2)
    uint256 public sellFeeIncreaseFactor = 130;
    
    uint256 public marketingDivisor = 30;
    
    uint256 public _buyBackMultiplier = 100;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;
    
    address public presaleAddress = address(0);

    // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) public _isExcludedMaxSellTFransactionAmount;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) _blacklist;
    
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed from, address indexed to, uint value);
    
    constructor() BEP20("LanaCake", "LANA") {
        balances[msg.sender] = totalSupply;

        /*
        _mint is an internal function in BEP20.sol that is only called here,
        and CANNOT be called ever again
        */
        _mint(owner(), totalSupply);
    }

    function whitelistDxSale(address _presaleAddress, address _routerAddress) public onlyOwner {
  	    presaleAddress = _presaleAddress;
  	}

    function setMaxBuyTransaction(uint256 maxTokens) external onlyOwner {
  	    maxBuyTranscationAmount = maxTokens * 10 ** decimals();
  	}
  	
  	function setMaxSellTransaction(uint256 maxTokens) external onlyOwner {
  	    maxSellTransactionAmount = maxTokens * 10 ** decimals();
  	}
  	
  	function setMaxWalletToken(uint256 maxTokens) external onlyOwner {
  	    maxWalletToken = maxTokens * 10 ** decimals();
  	}

    function setSellTransactionMultiplier(uint256 multiplier) external onlyOwner {
  	    require(sellFeeIncreaseFactor >= 100 && sellFeeIncreaseFactor <= 200, "DaughterDoge: Sell transaction multipler must be between 100 (1x) and 200 (2x)");
  	    sellFeeIncreaseFactor = multiplier;
  	}
  	
  	function setMarketingDivisor(uint256 divisor) external onlyOwner {
  	    require(marketingDivisor >= 0 && marketingDivisor <= 100, "DaughterDoge: Marketing divisor must be between 0 (0%) and 100 (100%)");
  	    sellFeeIncreaseFactor = divisor;
  	}

    function prepareForPreSale() external onlyOwner {
        setTradingIsEnabled(false);
        maxBuyTranscationAmount = totalSupply();
        maxWalletToken = totalSupply();
    }
    
    function afterPreSale() external onlyOwner {
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
        require(!swapping, "LanaCake: A swapping process is currently running, wait till that is complete");
        
        uint256 buyBackBalance = address(this).balance;
        swapBNBForTokens(buyBackBalance / 10**2 * amount);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "DaughterDoge: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "DaughterDoge: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }
}
