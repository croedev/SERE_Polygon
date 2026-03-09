// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title  SERE Token (ERC20) — Polygon Mainnet
 * @notice Commemorative token based on the 1626 Baptism of Jesus.
 *         Initial Supply : 1,200,000,000 SERE
 *         Max Supply     : 12,000,000,000 SERE
 * @author K-Fandom Foundation / KDCA Technical Support
 */

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SEREToken is ERC20, ERC20Burnable, ERC20Pausable, ERC20Permit, Ownable {

    // ---------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------

    /// @notice Tokens minted at deployment: 1,200,000,000 SERE.
    uint256 public constant INITIAL_SUPPLY = 1_200_000_000 * 10**18;

    /// @notice Hard cap on total token supply: 12,000,000,000 SERE.
    uint256 public constant MAX_SUPPLY = 12_000_000_000 * 10**18;

    /// @notice Maximum tokens mintable in a single transaction (1% of MAX_SUPPLY).
    uint256 public constant MAX_MINT_PER_TX = MAX_SUPPLY / 100;

    // ---------------------------------------------------------------
    // State Variables
    // ---------------------------------------------------------------

    /// @dev Addresses prohibited from sending or receiving tokens.
    mapping(address => bool) private _blacklist;

    /// @dev Amount of tokens locked per address.
    mapping(address => uint256) private _lockupAmount;

    /// @dev Unix timestamp after which locked tokens become transferable.
    mapping(address => uint256) private _lockupReleaseTime;

    // ---------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------

    /// @notice Emitted when an address is added to or removed from the blacklist.
    event BlacklistUpdated(address indexed account, bool status);

    /// @notice Emitted when a token lockup is created.
    event LockupCreated(address indexed account, uint256 amount, uint256 releaseTime);

    /// @notice Emitted when a token lockup is released.
    event LockupReleased(address indexed account, uint256 amount);

    /// @notice Emitted when new SERE tokens are minted.
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Emitted when accidentally sent ERC20 tokens are recovered.
    event ERC20Recovered(address indexed token, address indexed to, uint256 amount);

    // ---------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------

    /// @dev Reverts if the given address is on the blacklist.
    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "SERE: account is blacklisted");
        _;
    }

    /// @dev Reverts if the given address is the zero address.
    modifier notZeroAddress(address account) {
        require(account != address(0), "SERE: zero address not allowed");
        _;
    }

    /// @dev Reverts if the given amount is zero.
    modifier positiveAmount(uint256 amount) {
        require(amount > 0, "SERE: amount must be greater than zero");
        _;
    }

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    /**
     * @notice Deploys the SERE token and mints the initial supply to the owner.
     * @dev    The initialOwner MUST be a 2-of-3 Gnosis Safe multisig wallet.
     * @param initialOwner Address that receives the initial supply and owner role.
     */
    constructor(address initialOwner)
        ERC20("SERE Token", "SERE")
        ERC20Permit("SERE Token")
        Ownable(initialOwner)
    {
        require(initialOwner != address(0), "SERE: owner is zero address");
        _mint(initialOwner, INITIAL_SUPPLY);
    }

    // ---------------------------------------------------------------
    // Ownership
    // ---------------------------------------------------------------

    /**
     * @notice renounceOwnership is permanently disabled.
     * @dev    Prevents accidental loss of multisig governance control.
     *         Declared as pure to satisfy compiler mutability requirements.
     */
    function renounceOwnership() public pure override {
        revert("SERE: renounceOwnership is disabled");
    }

    // ---------------------------------------------------------------
    // Transfer
    // ---------------------------------------------------------------

    /**
     * @notice Transfers tokens to a recipient.
     * @dev    Enforces blacklist check and lockup constraints on the sender.
     * @param to     Recipient address.
     * @param amount Number of tokens to transfer (in wei units).
     */
    function transfer(address to, uint256 amount)
        public
        override
        notBlacklisted(msg.sender)
        notBlacklisted(to)
        notZeroAddress(to)
        positiveAmount(amount)
        returns (bool)
    {
        _checkLockup(msg.sender, amount);
        return super.transfer(to, amount);
    }

    /**
     * @notice Transfers tokens on behalf of another address.
     * @dev    Enforces blacklist check and lockup constraints on the from address.
     * @param from   Address to transfer from.
     * @param to     Recipient address.
     * @param amount Number of tokens to transfer (in wei units).
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        override
        notBlacklisted(from)
        notBlacklisted(to)
        notBlacklisted(msg.sender)
        notZeroAddress(to)
        positiveAmount(amount)
        returns (bool)
    {
        _checkLockup(from, amount);
        return super.transferFrom(from, to, amount);
    }

    // ---------------------------------------------------------------
    // Lockup — Internal
    // ---------------------------------------------------------------

    /**
     * @dev Reverts if the requested transfer amount exceeds the
     *      unlocked balance of the given account.
     */
    function _checkLockup(address account, uint256 amount) internal view {
        if (_lockupAmount[account] > 0 && block.timestamp < _lockupReleaseTime[account]) {
            uint256 lockedBalance = _lockupAmount[account];
            uint256 currentBalance = balanceOf(account);
            require(currentBalance >= lockedBalance, "SERE: invalid lockup state");
            uint256 available = currentBalance - lockedBalance;
            require(amount <= available, "SERE: amount exceeds unlocked balance");
        }
    }

    // ---------------------------------------------------------------
    // Pause  (onlyOwner — requires 2-of-3 multisig)
    // ---------------------------------------------------------------

    /// @notice Pauses all token transfers. Requires multisig consensus.
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Resumes all token transfers. Requires multisig consensus.
    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------
    // Minting  (onlyOwner — requires 2-of-3 multisig)
    // ---------------------------------------------------------------

    /**
     * @notice Mints additional SERE tokens.
     * @dev    Total supply must not exceed MAX_SUPPLY.
     *         A single call must not exceed MAX_MINT_PER_TX (1% of MAX_SUPPLY).
     *         Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param to     Recipient address.
     * @param amount Number of tokens to mint (in wei units).
     */
    function mint(address to, uint256 amount)
        external
        onlyOwner
        notZeroAddress(to)
        positiveAmount(amount)
    {
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "SERE: exceeds max supply"
        );
        require(
            amount <= MAX_MINT_PER_TX,
            "SERE: exceeds max mint per transaction (1% of MAX_SUPPLY)"
        );
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    // ---------------------------------------------------------------
    // Blacklist  (onlyOwner — requires 2-of-3 multisig)
    // ---------------------------------------------------------------

    /**
     * @notice Adds an address to the blacklist.
     * @dev    Used for AML and fraud-prevention purposes.
     *         Cannot blacklist the owner or zero address.
     *         Reverts if the address is already blacklisted.
     *         Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param account Address to blacklist.
     */
    function addToBlacklist(address account)
        external
        onlyOwner
        notZeroAddress(account)
    {
        require(account != owner(), "SERE: cannot blacklist owner");
        require(!_blacklist[account], "SERE: already blacklisted");
        _blacklist[account] = true;
        emit BlacklistUpdated(account, true);
    }

    /**
     * @notice Removes an address from the blacklist.
     * @dev    Reverts if the address is not currently blacklisted.
     *         Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param account Address to remove from the blacklist.
     */
    function removeFromBlacklist(address account)
        external
        onlyOwner
        notZeroAddress(account)
    {
        require(_blacklist[account], "SERE: not blacklisted");
        _blacklist[account] = false;
        emit BlacklistUpdated(account, false);
    }

    /**
     * @notice Returns true if the given address is blacklisted.
     * @param account Address to query.
     */
    function isBlacklisted(address account) external view returns (bool) {
        return _blacklist[account];
    }

    // ---------------------------------------------------------------
    // Lockup  (write: onlyOwner — release: permissionless)
    // ---------------------------------------------------------------

    /**
     * @notice Locks a specified token amount for an address until releaseTime.
     * @dev    The account must already hold at least `amount` tokens.
     *         Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param account     Address whose tokens will be locked.
     * @param amount      Number of tokens to lock (in wei units).
     * @param releaseTime Unix timestamp after which the tokens unlock.
     */
    function createLockup(address account, uint256 amount, uint256 releaseTime)
        external
        onlyOwner
        notZeroAddress(account)
        positiveAmount(amount)
    {
        require(
            releaseTime > block.timestamp,
            "SERE: release time must be in the future"
        );
        require(
            balanceOf(account) >= amount,
            "SERE: insufficient balance for lockup"
        );
        _lockupAmount[account] = amount;
        _lockupReleaseTime[account] = releaseTime;
        emit LockupCreated(account, amount, releaseTime);
    }

    /**
     * @notice Forcibly removes a lockup before expiry (error correction only).
     * @dev    Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param account Address whose lockup will be removed.
     */
    function removeLockup(address account)
        external
        onlyOwner
        notZeroAddress(account)
    {
        require(_lockupAmount[account] > 0, "SERE: no lockup exists");
        uint256 amount = _lockupAmount[account];
        _lockupAmount[account] = 0;
        _lockupReleaseTime[account] = 0;
        emit LockupReleased(account, amount);
    }

    /**
     * @notice Releases an expired lockup. Can be called by anyone.
     * @dev    Reverts if the lockup period has not yet ended.
     * @param account Address whose lockup will be released.
     */
    function releaseLockup(address account)
        external
        notZeroAddress(account)
    {
        require(_lockupAmount[account] > 0, "SERE: no lockup exists");
        require(
            block.timestamp >= _lockupReleaseTime[account],
            "SERE: lockup period not ended"
        );
        uint256 amount = _lockupAmount[account];
        _lockupAmount[account] = 0;
        _lockupReleaseTime[account] = 0;
        emit LockupReleased(account, amount);
    }

    /**
     * @notice Returns the lockup amount and release time for an address.
     * @param account Address to query.
     * @return amount      Locked token amount (in wei units).
     * @return releaseTime Unix timestamp when the lockup expires.
     */
    function getLockupInfo(address account)
        external
        view
        returns (uint256 amount, uint256 releaseTime)
    {
        return (_lockupAmount[account], _lockupReleaseTime[account]);
    }

    /**
     * @notice Returns the transferable (unlocked) balance of an address.
     * @param account Address to query.
     * @return Unlocked token balance (in wei units).
     */
    function getUnlockedBalance(address account) external view returns (uint256) {
        uint256 balance = balanceOf(account);
        if (
            _lockupAmount[account] > 0 &&
            block.timestamp < _lockupReleaseTime[account]
        ) {
            if (balance >= _lockupAmount[account]) {
                return balance - _lockupAmount[account];
            }
            return 0;
        }
        return balance;
    }

    // ---------------------------------------------------------------
    // ERC20 Recovery  (onlyOwner — requires 2-of-3 multisig)
    // ---------------------------------------------------------------

    /**
     * @notice Recovers ERC20 tokens accidentally sent to this contract.
     * @dev    SERE token itself cannot be recovered to prevent misuse.
     *         Requires 2-of-3 Gnosis Safe multisig consensus.
     * @param token  Address of the ERC20 token to recover (not SERE).
     * @param to     Address to send the recovered tokens to.
     * @param amount Number of tokens to recover (in wei units).
     */
    function recoverERC20(address token, address to, uint256 amount)
        external
        onlyOwner
        notZeroAddress(token)
        notZeroAddress(to)
        positiveAmount(amount)
    {
        require(token != address(this), "SERE: cannot recover SERE token");
        bool success = IERC20(token).transfer(to, amount);
        require(success, "SERE: ERC20 transfer failed");
        emit ERC20Recovered(token, to, amount);
    }

    // ---------------------------------------------------------------
    // Internal Override
    // ---------------------------------------------------------------

    /// @dev Required override to resolve diamond inheritance between ERC20 and ERC20Pausable.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
