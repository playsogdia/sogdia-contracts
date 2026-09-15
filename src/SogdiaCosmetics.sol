// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// Sogdia game items, sold only through the bound marketplace.
/// Non-upgradeable; immutable per-product metadata/cap; lifetime issuance never resets.
contract SogdiaCosmetics is ERC1155Supply, Ownable2Step {
    struct Product { bool exists; uint256 cap; uint256 minted; string metadata; }
    mapping(uint256 => Product) private products;
    address public marketplace;
    error InvalidInput();
    error Unavailable();
    event ProductCreated(uint256 indexed id, uint256 cap, string metadata);
    event MarketplaceBound(address indexed marketplace);
    constructor(address initialOwner) ERC1155("") Ownable(initialOwner) {}
    /// cap=0 explicitly denotes an unlimited standard collection, not sold out.
    function createProduct(uint256 id, uint256 cap, string calldata metadata) external onlyOwner {
        if (id == 0 || products[id].exists || bytes(metadata).length == 0) revert InvalidInput();
        products[id] = Product(true, cap, 0, metadata);
        emit ProductCreated(id, cap, metadata);
        emit URI(metadata, id);
    }
    function bindMarketplace(address market) external onlyOwner {
        if (marketplace != address(0) || market.code.length == 0) revert InvalidInput();
        marketplace = market;
        emit MarketplaceBound(market);
    }
    function product(uint256 id) external view returns (bool exists, uint256 cap, uint256 minted, string memory metadata) {
        Product storage p = products[id]; return (p.exists, p.cap, p.minted, p.metadata);
    }
    function uri(uint256 id) public view override returns (string memory) { return products[id].metadata; }
    function mintPurchase(address buyer, uint256 id, uint256 amount) external {
        if (msg.sender != marketplace) revert Unavailable();
        Product storage p = products[id];
        if (!p.exists || buyer == address(0) || amount == 0) revert InvalidInput();
        uint256 issued = p.minted + amount;
        if (p.cap != 0 && issued > p.cap) revert Unavailable();
        p.minted = issued;
        _mint(buyer, id, amount, "");
    }
    // No owner mint, burn, metadata edit, cap edit, upgrade, or collection replacement.
}
