// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol"; 
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";


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
    

    modifier onlyHomeChain() {
        if (block.chainid != homeChainId) revert NotHomeChain();
        _;
    }
    
    
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
    
    
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(msg.sender, block.timestamp);
    }
    
    
    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpause(msg.sender, block.timestamp);
    }
    
    // ============ Supply Management ============
    
    
    function setMintingEnabled(bool _enabled) external onlyOwner {
        mintingEnabled = _enabled;
        emit MintingStatusChanged(_enabled);
    }
    
    
    function setBurningEnabled(bool _enabled) external onlyOwner {
        burningEnabled = _enabled;
        emit BurningStatusChanged(_enabled);
    }
    
    
    function setBridgingEnabled(bool _enabled) external onlyOwner {
        bridgingEnabled = _enabled;
        emit BridgingStatusChanged(_enabled);
    }
    
    // ============ Token Functions ============
    
    
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
    
    
    function burn(uint256 amount) external whenNotPaused {
        if (!burningEnabled) revert BurningDisabled();
        
        _burn(msg.sender, amount);
        
        // Update chain supply tracking
        chainSupply[uint32(block.chainid)] -= amount;
        
        emit TokensBurned(msg.sender, amount);
        emit ChainSupplyUpdated(uint32(block.chainid), chainSupply[uint32(block.chainid)]);
    }
    
    
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
    
    
    function mintableSupply() public view returns (uint256) {
        // Only home chain can mint
        if (block.chainid != homeChainId) return 0;
        if (!mintingEnabled) return 0;
        if (maxSupply == 0) return type(uint256).max; 
        
        uint256 current = totalSupply();
        if (current >= maxSupply) return 0;
        return maxSupply - current;
    }
    
    
    function canMint(uint256 amount) public view returns (bool) {
        if (block.chainid != homeChainId) return false;
        if (!mintingEnabled) return false;
        if (maxSupply == 0) return true; // Unlimited
        return totalSupply() + amount <= maxSupply;
    }
    
    
    function isHomeChain() public view returns (bool) {
        return block.chainid == homeChainId;
    }
    
    
    function currentChainSupply() public view returns (uint256) {
        return totalSupply();
    }
    
    // ============ Pausable Overrides ============
    
    
    function transfer(address to, uint256 value) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transfer(to, value);
    }
    
    
    function transferFrom(address from, address to, uint256 value) 
        public 
        override 
        whenNotPaused 
        returns (bool) 
    {
        return super.transferFrom(from, to, value);
    }
    
    // ============ OFT Overrides for Cross-Chain ============
    
    
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
    
    
    function updateChainSupply(uint32 chainId, uint256 supply) 
        external 
        onlyOwner 
    {
        chainSupply[chainId] = supply;
        emit ChainSupplyUpdated(chainId, supply);
    }
}
