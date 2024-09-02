// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract THCToken is ERC20, Ownable, ReentrancyGuard {
    ERC20 public HYBRID;
    IUniswapV2Router02 public uniswapV2Router;
    address public marketingWallet;
    
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant REWARD_INTERVAL = 45 minutes;
    uint256 public constant REWARD_PERCENT = 3;
    uint256 public constant TAX_PERCENT = 4;
    uint256 public constant REWARD_TAX = 2;
    uint256 public constant MARKETING_TAX = 2;

    mapping(address => uint256) private _lastRewardTime;
    mapping(address => bool) private _excludedFromTax;

    event RewardPaid(address indexed user, uint256 amount);
    event RewardCalculated(address indexed user, uint256 calculatedReward, uint256 contractBalance);
    event RewardNotPaid(address indexed user, uint256 calculatedReward, uint256 contractBalance);

    constructor(address _marketingWallet, address _uniswapRouter, address _hybridToken) 
        ERC20("3% THC", "THC") 
        Ownable(msg.sender)
    {
        marketingWallet = _marketingWallet;
        // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D UniswapV2Router02 is deployed at 
        uniswapV2Router = IUniswapV2Router02(_uniswapRouter);
        HYBRID = ERC20(_hybridToken);

        uint256 ownerSupply = TOTAL_SUPPLY / 10; // 10% to owner
        uint256 marketingSupply = ownerSupply; // 10% to marketing wallet
        uint256 publicSupply = TOTAL_SUPPLY - ownerSupply - marketingSupply; // Remaining 80%

        _mint(msg.sender, ownerSupply);
        _mint(marketingWallet, marketingSupply);
        _mint(address(this), publicSupply);

        _excludedFromTax[msg.sender] = true;
        _excludedFromTax[marketingWallet] = true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        return _transferWithTax(_msgSender(), recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transferWithTax(sender, recipient, amount);
        uint256 currentAllowance = allowance(sender, _msgSender());
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

    function _transferWithTax(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _updateReward(sender);
        _updateReward(recipient);

        uint256 taxAmount = 0;
        if (!_excludedFromTax[sender] && !_excludedFromTax[recipient]) {
            taxAmount = (amount * TAX_PERCENT) / 100;
        }

        uint256 rewardTaxAmount = (taxAmount * REWARD_TAX) / TAX_PERCENT;
        uint256 marketingTaxAmount = taxAmount - rewardTaxAmount;

        _transfer(sender, address(this), rewardTaxAmount);
        _transfer(sender, marketingWallet, marketingTaxAmount);
        _transfer(sender, recipient, amount - taxAmount);

        return true;
    }

    function _updateReward(address account) internal {
        uint256 timeElapsed = block.timestamp - _lastRewardTime[account];
        if (timeElapsed >= REWARD_INTERVAL) {
            uint256 rewards = (balanceOf(account) * REWARD_PERCENT * (timeElapsed / REWARD_INTERVAL)) / 100;
            emit RewardCalculated(account, rewards, HYBRID.balanceOf(address(this)));
            if (rewards > 0 && HYBRID.balanceOf(address(this)) >= rewards) {
                HYBRID.transfer(account, rewards);
                emit RewardPaid(account, rewards);
            } else {
                emit RewardNotPaid(account, rewards, HYBRID.balanceOf(address(this)));
            }
            _lastRewardTime[account] = block.timestamp;
        }
    }

    function claimRewards() external nonReentrant {
        _updateReward(msg.sender);
    }

    function swapTHCForHYBRID() public onlyOwner {
        uint256 contractTHCBalance = balanceOf(address(this));
        require(contractTHCBalance > 0, "No THC balance to swap");

        _approve(address(this), address(uniswapV2Router), contractTHCBalance);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(HYBRID);

        uniswapV2Router.swapExactTokensForTokens(
            contractTHCBalance,
            0, // Accept any amount of HYBRID
            path,
            address(this),
            block.timestamp
        );
    }

    // New function to receive HYBRID tokens
    function fundRewards(uint256 amount) external onlyOwner {
        require(HYBRID.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }

    // Modified swap function to convert accumulated THC to HYBRID for rewards
    function swapAccumulatedTHCForRewards() external onlyOwner {
        uint256 accumulatedTHC = balanceOf(address(this));
        require(accumulatedTHC > 0, "No accumulated THC to swap");

        _approve(address(this), address(uniswapV2Router), accumulatedTHC);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(HYBRID);

        uniswapV2Router.swapExactTokensForTokens(
            accumulatedTHC,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function excludeFromTax(address account) external onlyOwner {
        _excludedFromTax[account] = true;
    }

    function includeInTax(address account) external onlyOwner {
        _excludedFromTax[account] = false;
    }

    function renounceOwnership() public virtual override onlyOwner {
        _transferOwnership(address(0));
    }
}



/*
you can deploy these contract on remix id  for testing 


1. deploy the reward token contract 
2. copy the address, copy the  uniswaprouter address , 
3. deploy the tch token with same wallet address  
5. now what u have to do is copy the address of tch token address => call the transfer function of reward contract
send the reward (Hybrid )token to the tch contract make sure to send all  
6.now Do the  working of ur mechanaism and users who hold tokens will receive hybrid tokens based on their holdings
*/

