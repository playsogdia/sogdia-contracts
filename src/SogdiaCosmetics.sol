// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

/// The bound marketplace's immutable reserve and commission, read once at binding.
interface ISogdiaMarketTerms {
    function rewardReserve() external view returns (address);
    function feeBps() external view returns (uint16);
}

/// Sogdia game items, sold only through the bound marketplace.
/// Non-upgradeable; immutable per-product metadata/cap; lifetime issuance never resets.
/// External marketplaces such as OpenSea:
/// - ERC-2981 royalty equal to the bound marketplace's commission, paid to its reward reserve, set once at
///   `bindMarketplace` and never changeable, so resales elsewhere can pay the same 2.5% to the pool.
///   Whether a given external marketplace honours ERC-2981 is up to that marketplace.
/// - ERC-7572 `contractURI` for collection name, logo and description; owner-updatable. Each product's
///   own metadata URI stays immutable.
contract SogdiaCosmetics is ERC1155Supply, ERC2981, Ownable2Step {
    struct Product { bool exists; uint256 cap; uint256 minted; string metadata; }
    mapping(uint256 => Product) private products;
    address public marketplace;
    string private collectionURI;
    error InvalidInput();
    error Unavailable();
    event ProductCreated(uint256 indexed id, uint256 cap, string metadata);
    event MarketplaceBound(address indexed marketplace);
    /// ERC-7572.
    event ContractURIUpdated();
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
        ISogdiaMarketTerms terms = ISogdiaMarketTerms(market);
        _setDefaultRoyalty(terms.rewardReserve(), terms.feeBps());
        emit MarketplaceBound(market);
    }
    function contractURI() external view returns (string memory) { return collectionURI; }
    function setContractURI(string calldata newURI) external onlyOwner {
        if (bytes(newURI).length == 0) revert InvalidInput();
        collectionURI = newURI;
        emit ContractURIUpdated();
    }
    function supportsInterface(bytes4 id) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(id);
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
