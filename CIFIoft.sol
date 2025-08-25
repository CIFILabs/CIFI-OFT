// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/security/Pausable.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

contract CIFIOFT3 is OFT, Pausable {
    // ============ Supply Management State ============
    uint256 public immutable maxSupply;
    bool public mintingEnabled = true;
    bool public burningEnabled = true;
    
    // ============ Custom Errors ============
    error ExceedsMaxSupply(uint256 requested, uint256 max);
    error MintingDisabled();
    error BurningDisabled();
    
    // ============ Events ============
    event EmergencyPause(address indexed by, uint256 timestamp);
    event EmergencyUnpause(address indexed by, uint256 timestamp);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event MintingStatusChanged(bool enabled);
    event BurningStatusChanged(bool enabled);
    event CrossChainTransferSent(
        address indexed from,
        uint32 indexed dstEid,
        uint256 amount
    );
    event CrossChainTransferReceived(
        address indexed to,
        uint32 indexed srcEid,
        uint256 amount
    );
    
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        uint256 _maxSupply
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) Ownable(_delegate) {
        maxSupply = _maxSupply; // Can be 0 for unlimited
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
    
    // ============ Token Functions ============
    
    function mint(address to, uint256 amount) public onlyOwner whenNotPaused {
        if (!mintingEnabled) revert MintingDisabled();
        if (maxSupply > 0 && totalSupply() + amount > maxSupply) {
            revert ExceedsMaxSupply(totalSupply() + amount, maxSupply);
        }
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }
    
    function burn(uint256 amount) public whenNotPaused {
        if (!burningEnabled) revert BurningDisabled();
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }
    
    // ============ View Functions ============
    
    function mintableSupply() public view returns (uint256) {
        if (maxSupply == 0) return type(uint256).max; // Unlimited
        if (!mintingEnabled) return 0;
        
        uint256 current = totalSupply();
        if (current >= maxSupply) return 0;
        return maxSupply - current;
    }
    
    function canMint(uint256 amount) public view returns (bool) {
        if (!mintingEnabled) return false;
        if (maxSupply == 0) return true; // Unlimited
        return totalSupply() + amount <= maxSupply;
    }
    
    // ============ Pausable Overrides ============
    
    function transfer(
        address to, 
        uint256 value
    ) public override whenNotPaused returns (bool) {
        return super.transfer(to, value);
    }
    
    function transferFrom(
        address from, 
        address to, 
        uint256 value
    ) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, value);
    }
    
    // ============ OFT Overrides for Cross-Chain ============
    
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override whenNotPaused returns (
        uint256 amountSentLD, 
        uint256 amountReceivedLD
    ) {
        (amountSentLD, amountReceivedLD) = super._debit(_from, _amountLD, _minAmountLD, _dstEid);
        emit CrossChainTransferSent(_from, _dstEid, amountSentLD);
        return (amountSentLD, amountReceivedLD);
    }
    
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal override whenNotPaused returns (uint256 amountReceivedLD) {
        amountReceivedLD = super._credit(_to, _amountLD, _srcEid);
        emit CrossChainTransferReceived(_to, _srcEid, amountReceivedLD);
        return amountReceivedLD;
    }
}
