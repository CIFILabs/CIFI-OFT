// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol"; 
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/**
 * @title CIFIOFT
 * @notice Omnichain Fungible Token with enhanced supply management and emergency controls
 * @dev Implements cross-chain token transfers via LayerZero with proper supply tracking
 */
contract CIFIOFT is OFT, Pausable {
    // ============ Supply Management State ============
    uint256 public immutable maxSupply;
    uint256 public immutable homeChainId; 
    bool public mintingEnabled = true;
    bool public burningEnabled = true;
    bool public bridgingEnabled = true;
    
    mapping(uint32 => uint256) public chainSupply;
    
    // ============ Custom Errors ============
    error ExceedsMaxSupply(uint256 requested, uint256 available);
    error MintingDisabled();
    error BurningDisabled();
    error BridgingDisabled();
    error NotHomeChain();
    error InvalidChainId();
    
    // ============ Events ============
    event EmergencyPause(address indexed by, uint256 timestamp);
    event EmergencyUnpause(address indexed by, uint256 timestamp);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event MintingStatusChanged(bool enabled);
    event BurningStatusChanged(bool enabled);
    event BridgingStatusChanged(bool enabled);
    event CrossChainTransferSent(
        address indexed from,
        uint32 indexed dstEid,
        uint256 amount,
        bytes32 indexed guid
    );
    event CrossChainTransferReceived(
        address indexed to,
        uint32 indexed srcEid,
        uint256 amount,
        bytes32 indexed guid
    );
    event ChainSupplyUpdated(uint32 indexed chainId, uint256 newSupply);
    
    // ============ Modifiers ============
    
    /**
     * @notice Ensures function can only be called on the home chain
     */
    modifier onlyHomeChain() {
        if (block.chainid != homeChainId) revert NotHomeChain();
        _;
    }
    
    /**
     * @notice Ensures bridging is enabled
     */
    modifier whenBridgingEnabled() {
        if (!bridgingEnabled) revert BridgingDisabled();
        _;
    }
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        uint256 _maxSupply,
        uint256 _homeChainId
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        maxSupply = _maxSupply;
        homeChainId = _homeChainId;
        
        // Initialize supply tracking for home chain
        if (_homeChainId == block.chainid) {
            chainSupply[uint32(block.chainid)] = 0;
        }
    }
    
    // ============ Emergency Controls ============
    
    /**
     * @notice Pauses all token operations including transfers and bridging
     * @dev Can only be called by owner
     */
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }
    
    /**
     * @notice Unpauses all token operations
     * @dev Can only be called by owner
     */
    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }
    
    // ============ Supply Management ============
    
    /**
     * @notice Enables or disables minting functionality
     * @param _enabled True to enable, false to disable
     */
    function setMintingEnabled(bool _enabled) external onlyOwner {
        mintingEnabled = _enabled;
        emit MintingStatusChanged(_enabled);
    }
    
    /**
     * @notice Enables or disables burning functionality
     * @param _enabled True to enable, false to disable
     */
    function setBurningEnabled(bool _enabled) external onlyOwner {
        burningEnabled = _enabled;
        emit BurningStatusChanged(_enabled);
    }
    
    /**
     * @notice Enables or disables cross-chain bridging
     * @param _enabled True to enable, false to disable
     */
    function setBridgingEnabled(bool _enabled) external onlyOwner {
        bridgingEnabled = _enabled;
        emit BridgingStatusChanged(_enabled);
    }
    
    // ============ Token Functions ============
    
    /**
     * @notice Mints new tokens (only on home chain)
     * @param to Recipient address
     * @param amount Amount to mint
     * @dev Can only mint on the designated home chain to maintain global supply cap
     */
    function mint(address to, uint256 amount) 
        external 
        onlyOwner 
        onlyHomeChain 
        whenNotPaused 
    {
        if (!mintingEnabled) revert MintingDisabled();
        
        // Check against max supply
        if (maxSupply > 0) {
            uint256 currentTotal = totalSupply();
            if (currentTotal + amount > maxSupply) {
                revert ExceedsMaxSupply(amount, maxSupply - currentTotal);
            }
        }
        
        _mint(to, amount);
        
        // Update chain supply tracking
        chainSupply[uint32(block.chainid)] += amount;
        
        emit TokensMinted(to, amount);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
    }
    
    /**
     * @notice Burns tokens from the caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external whenNotPaused {
        if (!burningEnabled) revert BurningDisabled();
        
        _burn(msg.sender, amount);
        
        // Update chain supply tracking
        chainSupply[uint32(block.chainid)] -= amount;
        
        emit TokensBurned(msg.sender, amount);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
    }
    
    /**
     * @notice Burns tokens from a specific account (requires approval)
     * @param from Account to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) 
        external 
        whenNotPaused 
    {
        if (!burningEnabled) revert BurningDisabled();
        
        // This will check allowance internally
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        
        // Update chain supply tracking
        chainSupply[uint32(block.chainid)] -= amount;
        
        emit TokensBurned(from, amount);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Returns the remaining mintable supply
     * @return Amount that can still be minted (only relevant on home chain)
     */
    function mintableSupply() public view returns (uint256) {
        // Only home chain can mint
        if (block.chainid != homeChainId) return 0;
        if (!mintingEnabled) return 0;
        if (maxSupply == 0) return type(uint256).max; 
        
        uint256 current = totalSupply();
        if (current >= maxSupply) return 0;
        return maxSupply - current;
    }
    
    /**
     * @notice Checks if a specific amount can be minted
     * @param amount Amount to check
     * @return True if the amount can be minted
     */
    function canMint(uint256 amount) public view returns (bool) {
        if (block.chainid != homeChainId) return false;
        if (!mintingEnabled) return false;
        if (maxSupply == 0) return true; // Unlimited
        return totalSupply() + amount <= maxSupply;
    }
    
    /**
     * @notice Returns whether this is the home chain
     * @return True if current chain is the home chain
     */
    function isHomeChain() public view returns (bool) {
        return block.chainid == homeChainId;
    }
    
    /**
     * @notice Gets the current chain's supply
     * @return Current supply on this chain
     */
    function currentChainSupply() public view returns (uint256) {
        return totalSupply();
    }
    
    // ============ Pausable Overrides ============
    
    /**
     * @dev Override transfer to add pause functionality
     */
    function transfer(address to, uint256 value) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, value);
    }
    
    /**
     * @dev Override transferFrom to add pause functionality
     */
    function transferFrom(address from, address to, uint256 value) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transferFrom(from, to, value);
    }
    
    // ============ OFT Overrides for Cross-Chain ============
    
    /**
     * @dev Internal function to handle outgoing cross-chain transfers
     * @param _from Sender address
     * @param _amountLD Amount in local decimals
     * @param _minAmountLD Minimum amount to receive
     * @param _dstEid Destination endpoint ID
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override whenNotPaused whenBridgingEnabled returns (
        uint256 amountSentLD, 
        uint256 amountReceivedLD
    ) {
        (amountSentLD, amountReceivedLD) = super._debit(_from, _amountLD, _minAmountLD, _dstEid);
        
        // Update local chain supply tracking
        chainSupply[uint32(block.chainid)] -= amountSentLD;
        
        // Generate a pseudo-GUID for tracking (in production, get from LayerZero)
        bytes32 guid = keccak256(abi.encodePacked(_from, _dstEid, amountSentLD, block.timestamp));
        
        emit CrossChainTransferSent(_from, _dstEid, amountSentLD, guid);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
        
        return (amountSentLD, amountReceivedLD);
    }
    
    /**
     * @dev Internal function to handle incoming cross-chain transfers
     * @param _to Recipient address
     * @param _amountLD Amount in local decimals
     * @param _srcEid Source endpoint ID
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override whenNotPaused whenBridgingEnabled returns (uint256 amountReceivedLD) {
        amountReceivedLD = super._credit(_to, _amountLD, _srcEid);
        
        // Update local chain supply tracking
        chainSupply[uint32(block.chainid)] += amountReceivedLD;
        
        // Generate a pseudo-GUID for tracking
        bytes32 guid = keccak256(abi.encodePacked(_to, _srcEid, amountReceivedLD, block.timestamp));
        
        emit CrossChainTransferReceived(_to, _srcEid, amountReceivedLD, guid);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
        
        return amountReceivedLD;
    }
    
    // ============ Supply Synchronization (Optional Advanced Feature) ============
    
    /**
     * @notice Updates supply tracking for a specific chain (owner only)
     * @param chainId Chain ID to update
     * @param supply New supply value
     * @dev This is for manual correction if supply tracking gets out of sync
     */
    function updateChainSupply(uint32 chainId, uint256 supply) 
        external 
        onlyOwner 
    {
        chainSupply[chainId] = supply;
        emit ChainSupplyUpdated(chainId, supply);
    }
}
