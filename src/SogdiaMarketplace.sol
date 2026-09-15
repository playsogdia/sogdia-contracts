// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "./SogdiaCosmetics.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// Custom primary store and escrow resale. No arbitrary token/NFT routing or admin withdrawal.
/// Only plain non-taxed/non-rebasing ERC20. Fees apply to this marketplace, not outside transfers.
///
/// Owner controls and their limits:
/// - The owner may update an offer's price and window (`updateOffer`). Supply caps stay immutable in
///   SogdiaCosmetics. A buyer is protected by `expectedTotal`: a price change between quote and
///   inclusion reverts the purchase instead of charging the new price.
/// - The owner may pause new primary purchases, new listings and listing purchases. `cancel` is never
///   paused, so escrowed items can always return to their sellers.
/// - Ownership cannot be renounced: a renounced, paused market could never resume sales.
///   The intended production owner is a Safe multisig accepted through Ownable2Step.
contract SogdiaMarketplace is Ownable2Step, Pausable, ReentrancyGuard, ERC165, IERC1155Receiver {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    SogdiaCosmetics public immutable cosmetics;
    address public immutable rewardReserve;
    uint16 public immutable feeBps;
    struct Offer { uint256 price; uint64 start; uint64 end; }
    struct Listing { address seller; uint256 item; uint256 remaining; uint256 unitPrice; uint64 expiry; }
    mapping(uint256 => Offer) public offers;
    mapping(uint256 => Listing) public listings;
    uint256 public nextListing = 1;
    address private receivingFrom;
    uint256 private receivingItem;
    uint256 private receivingAmount;
    error InvalidInput();
    error Unavailable();
    error UnsupportedTransfer();
    event OfferCreated(uint256 indexed item, uint256 price, uint64 start, uint64 end);
    event OfferUpdated(uint256 indexed item, uint256 price, uint64 start, uint64 end);
    event Purchased(address indexed buyer, uint256 indexed item, uint256 amount, uint256 paid);
    event Listed(uint256 indexed listing, address indexed seller, uint256 indexed item, uint256 amount, uint256 unitPrice, uint64 expiry);
    event Sold(uint256 indexed listing, address indexed buyer, uint256 amount, uint256 paid, uint256 fee);
    event Cancelled(uint256 indexed listing, uint256 amount);
    constructor(IERC20 paymentToken, SogdiaCosmetics collection, address reserve, uint16 commissionBps, address initialOwner) Ownable(initialOwner) {
        if (address(paymentToken).code.length == 0 || address(collection).code.length == 0 || reserve == address(0) || reserve == address(this) || commissionBps >= 10000) revert InvalidInput();
        token = paymentToken; cosmetics = collection; rewardReserve = reserve; feeBps = commissionBps;
    }
    /// First terms for an existing product, once. Later changes go through `updateOffer`.
    function createOffer(uint256 item, uint256 price, uint64 start, uint64 end) external onlyOwner {
        (bool exists,,,) = cosmetics.product(item);
        if (!exists || price == 0 || offers[item].price != 0 || (end != 0 && (end <= start || end <= block.timestamp))) revert InvalidInput();
        offers[item] = Offer(price, start, end); emit OfferCreated(item, price, start, end);
    }
    /// New price and sale window for an existing offer. `end` may be in the past: that closes sales.
    /// `end == 0` keeps the offer open indefinitely. The supply cap is not touched.
    function updateOffer(uint256 item, uint256 price, uint64 start, uint64 end) external onlyOwner {
        if (offers[item].price == 0 || price == 0 || (end != 0 && end <= start)) revert InvalidInput();
        offers[item] = Offer(price, start, end); emit OfferUpdated(item, price, start, end);
    }
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }
    function renounceOwnership() public pure override { revert InvalidInput(); }
    function buyPrimary(uint256 item, uint256 amount, uint256 expectedTotal) external nonReentrant whenNotPaused {
        Offer memory o = offers[item];
        if (o.price == 0 || amount == 0 || block.timestamp < o.start || (o.end != 0 && block.timestamp >= o.end)) revert Unavailable();
        uint256 total = o.price * amount;
        if (total != expectedTotal) revert InvalidInput();
        _pay(msg.sender, rewardReserve, total);
        cosmetics.mintPurchase(msg.sender, item, amount);
        emit Purchased(msg.sender, item, amount, total);
    }
    function list(uint256 item, uint256 amount, uint256 unitPrice, uint64 expiry) external nonReentrant whenNotPaused returns (uint256 id) {
        if (amount == 0 || unitPrice == 0 || expiry <= block.timestamp || msg.sender == rewardReserve) revert InvalidInput();
        id = nextListing++;
        listings[id] = Listing(msg.sender, item, amount, unitPrice, expiry);
        receivingFrom = msg.sender; receivingItem = item; receivingAmount = amount;
        cosmetics.safeTransferFrom(msg.sender, address(this), item, amount, "");
        if (receivingFrom != address(0)) revert UnsupportedTransfer();
        emit Listed(id, msg.sender, item, amount, unitPrice, expiry);
    }
    function buyListing(uint256 id, uint256 amount, uint256 expectedTotal) external nonReentrant whenNotPaused {
        Listing storage l = listings[id];
        if (l.seller == address(0) || msg.sender == l.seller || amount == 0 || amount > l.remaining || block.timestamp >= l.expiry) revert Unavailable();
        uint256 total = l.unitPrice * amount;
        if (total != expectedTotal) revert InvalidInput();
        uint256 fee = Math.mulDiv(total, feeBps, 10000);
        l.remaining -= amount;
        _pay(msg.sender, l.seller, total - fee);
        if (fee != 0) _pay(msg.sender, rewardReserve, fee);
        cosmetics.safeTransferFrom(address(this), msg.sender, l.item, amount, "");
        emit Sold(id, msg.sender, amount, total, fee);
    }
    /// Never paused.
    function cancel(uint256 id) external nonReentrant {
        Listing storage l = listings[id];
        uint256 amount = l.remaining;
        if (msg.sender != l.seller || amount == 0) revert Unavailable();
        l.remaining = 0;
        cosmetics.safeTransferFrom(address(this), msg.sender, l.item, amount, "");
        emit Cancelled(id, amount);
    }
    function _pay(address from, address to, uint256 amount) private {
        if (from == to) revert InvalidInput();
        uint256 beforeFrom = token.balanceOf(from); uint256 beforeTo = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        if (token.balanceOf(from) != beforeFrom - amount || token.balanceOf(to) != beforeTo + amount) revert UnsupportedTransfer();
    }
    function onERC1155Received(address operator, address from, uint256 id, uint256 amount, bytes calldata) external override returns (bytes4) {
        if (msg.sender != address(cosmetics) || operator != address(this) || from != receivingFrom || from == address(0) || id != receivingItem || amount != receivingAmount) revert UnsupportedTransfer();
        receivingFrom = address(0); return this.onERC1155Received.selector;
    }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns (bytes4) { revert UnsupportedTransfer(); }
    function supportsInterface(bytes4 id) public view override(ERC165, IERC165) returns (bool) { return id == type(IERC1155Receiver).interfaceId || super.supportsInterface(id); }
}
