// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SERE Token - Polygon (ERC20)
 * @notice Initial Supply: 1,020,000,000 SERE / Max Supply: 12,000,000,000 SERE
 * @dev ERC20 token based on 1626 Baptism of Jesus Commemorative Coin
 * @author K-Fandom Foundation / KDCA Technical Support
 * @custom:security-contact security@kfandom.org
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SEREToken is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, Ownable {
    
    // Constants
    uint256 public constant INITIAL_SUPPLY = 1_200_000_000 * 10**18;
    uint256 public constant MAX_SUPPLY = 12_000_000_000 * 10**18;
    
    // State Variables
    mapping(address => bool) private _blacklist;
    mapping(address => uint256) private _lockupAmount;
    mapping(address => uint256) private _lockupReleaseTime;
    
    // Events
    event BlacklistUpdated(address indexed account, bool status);
    event LockupCreated(address indexed account, uint256 amount, uint256 releaseTime);
    event LockupReleased(address indexed account, uint256 amount);
    event TokensRecovered(address indexed from, address indexed to, uint256 amount, string reason);
    event TokensMinted(address indexed to, uint256 amount);
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);
    
    // Modifiers
    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "SERE: account is blacklisted");
        _;
    }
    
    // Constructor
    constructor(address initialOwner) 
        ERC20("SERE Token", "SERE") 
        ERC20Permit("SERE Token")
        Ownable(initialOwner)
    {
        require(initialOwner != address(0), "SERE: owner is zero address");
        _mint(initialOwner, INITIAL_SUPPLY);
    }
    
    // Transfer Functions
    function transfer(address to, uint256 amount) 
        public 
        override 
        notBlacklisted(msg.sender) 
        notBlacklisted(to)
        returns (bool) 
    {
        _checkLockup(msg.sender, amount);
        return super.transfer(to, amount);
    }
    
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notBlacklisted(from)
        notBlacklisted(to)
        notBlacklisted(msg.sender)
        returns (bool)
    {
        _checkLockup(from, amount);
        return super.transferFrom(from, to, amount);
    }
    
    function _checkLockup(address account, uint256 amount) internal view {
        if (_lockupAmount[account] > 0 && block.timestamp < _lockupReleaseTime[account]) {
            uint256 lockedBalance = _lockupAmount[account];
            uint256 currentBalance = balanceOf(account);
            require(currentBalance >= lockedBalance, "SERE: invalid lockup state");
            uint256 available = currentBalance - lockedBalance;
            require(amount <= available, "SERE: amount exceeds unlocked balance");
        }
    }
    
    // Pause Functions
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // Minting Function
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "SERE: mint to zero address");
        require(totalSupply() + amount <= MAX_SUPPLY, "SERE: exceeds max supply");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    // Blacklist Functions
    function addToBlacklist(address account) external onlyOwner {
        require(account != address(0), "SERE: zero address");
        require(account != owner(), "SERE: cannot blacklist owner");
        _blacklist[account] = true;
        emit BlacklistUpdated(account, true);
    }
    
    function removeFromBlacklist(address account) external onlyOwner {
        require(_blacklist[account], "SERE: not blacklisted");
        _blacklist[account] = false;
        emit BlacklistUpdated(account, false);
    }
    
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklist[account];
    }
    
    // Lockup Functions
    function createLockup(address account, uint256 amount, uint256 releaseTime) 
        external 
        onlyOwner 
    {
        require(account != address(0), "SERE: zero address");
        require(amount > 0, "SERE: amount is zero");
        require(releaseTime > block.timestamp, "SERE: release time must be future");
        require(balanceOf(account) >= amount, "SERE: insufficient balance for lockup");
        
        _lockupAmount[account] = amount;
        _lockupReleaseTime[account] = releaseTime;
        
        emit LockupCreated(account, amount, releaseTime);
    }
    
    function removeLockup(address account) external onlyOwner {
        require(_lockupAmount[account] > 0, "SERE: no lockup exists");
        
        uint256 amount = _lockupAmount[account];
        _lockupAmount[account] = 0;
        _lockupReleaseTime[account] = 0;
        
        emit LockupReleased(account, amount);
    }
    
    function releaseLockup(address account) external {
        require(_lockupAmount[account] > 0, "SERE: no lockup exists");
        require(block.timestamp >= _lockupReleaseTime[account], "SERE: lockup period not ended");
        
        uint256 amount = _lockupAmount[account];
        _lockupAmount[account] = 0;
        _lockupReleaseTime[account] = 0;
        
        emit LockupReleased(account, amount);
    }
    
    function getLockupInfo(address account) external view returns (uint256 amount, uint256 releaseTime) {
        return (_lockupAmount[account], _lockupReleaseTime[account]);
    }
    
    function getUnlockedBalance(address account) external view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (_lockupAmount[account] > 0 && block.timestamp < _lockupReleaseTime[account]) {
            if (balance >= _lockupAmount[account]) {
                return balance - _lockupAmount[account];
            }
            return 0;
        }
        return balance;
    }
    
    // Token Recovery Functions
    function recoverTokens(
        address from, 
        address to, 
        uint256 amount, 
        string calldata reason
    ) 
        external 
        onlyOwner 
    {
        require(from != address(0), "SERE: recover from zero address");
        require(to != address(0), "SERE: recover to zero address");
        require(amount > 0, "SERE: amount is zero");
        require(balanceOf(from) >= amount, "SERE: insufficient balance");
        require(bytes(reason).length > 0, "SERE: reason is required");
        
        _transfer(from, to, amount);
        emit TokensRecovered(from, to, amount, reason);
    }
    
    function recoverFromBlacklisted(address from, address to) 
        external 
        onlyOwner 
    {
        require(_blacklist[from], "SERE: address not blacklisted");
        require(to != address(0), "SERE: recover to zero address");
        
        uint256 amount = balanceOf(from);
        require(amount > 0, "SERE: no balance to recover");
        
        _transfer(from, to, amount);
        emit TokensRecovered(from, to, amount, "Recovered from blacklisted address");
    }
    
    function recoverERC20(address token, address to, uint256 amount) 
        external 
        onlyOwner 
    {
        require(token != address(0), "SERE: token is zero address");
        require(token != address(this), "SERE: cannot recover SERE token");
        require(to != address(0), "SERE: recover to zero address");
        require(amount > 0, "SERE: amount is zero");
        
        bool success = IERC20(token).transfer(to, amount);
        require(success, "SERE: ERC20 transfer failed");
        
        emit ERC20Recovered(token, to, amount);
    }
    
    // Required Override
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
