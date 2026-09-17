// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Supply} from "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

/// Sogdia game items, sold only through the bound marketplace.
/// Non-upgradeable; immutable per-product metadata/cap; lifetime issuance never resets.
/// External marketplaces such as OpenSea:
/// - ERC-2981 royalty for resales there, paid to an owner-set receiver at an owner-set rate of at most
///   `MAX_ROYALTY_BPS`. It is separate from the bound marketplace's own commission and never affects
///   sales through that marketplace. Whether an external marketplace honours ERC-2981 is up to it.
/// - `name()` and `symbol()`, which ERC-1155 does not define. A marketplace that indexes this
///   collection reads them for its title: without them OpenSea showed the contract address where the
///   name belongs, with the `contractURI` description right underneath it (checked on a throwaway
///   collection, 2026-09-16). They are constants because the collection is one collection forever.
/// - ERC-7572 `contractURI` for collection name, logo and description; owner-updatable. Each product's
///   own metadata URI stays immutable.
contract SogdiaCosmetics is ERC1155Supply, ERC2981, Ownable2Step {
    struct Product { bool exists; uint256 cap; uint256 minted; string metadata; }
    mapping(uint256 => Product) private products;
    string public constant name = "Sogdia";
    string public constant symbol = "SOGDIA";
    uint96 public constant MAX_ROYALTY_BPS = 1000;
    address public marketplace;
    string private collectionURI;
    error InvalidInput();
    error Unavailable();
    event ProductCreated(uint256 indexed id, uint256 cap, string metadata);
    event MarketplaceBound(address indexed marketplace);
    event RoyaltyUpdated(address indexed receiver, uint96 bps);
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
        emit MarketplaceBound(market);
    }
    /// Royalty on external marketplaces; no royalty is reported until this is first called.
    function setRoyalty(address receiver, uint96 bps) external onlyOwner {
        if (receiver == address(0) || bps > MAX_ROYALTY_BPS) revert InvalidInput();
        _setDefaultRoyalty(receiver, bps);
        emit RoyaltyUpdated(receiver, bps);
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
