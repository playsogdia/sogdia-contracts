// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "./SogdiaCosmetics.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// Primary store for SogdiaCosmetics products. No arbitrary token/NFT routing or admin withdrawal.
/// Only plain non-taxed/non-rebasing ERC20. Primary sales pay the full price to the reward reserve.
contract SogdiaMarketplace is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    SogdiaCosmetics public immutable cosmetics;
    address public immutable rewardReserve;
    uint16 public immutable feeBps;
    struct Offer { uint256 price; uint64 start; uint64 end; }
    mapping(uint256 => Offer) public offers;
    error InvalidInput();
    error Unavailable();
    error UnsupportedTransfer();
    event OfferCreated(uint256 indexed item, uint256 price, uint64 start, uint64 end);
    event Purchased(address indexed buyer, uint256 indexed item, uint256 amount, uint256 paid);
    constructor(IERC20 paymentToken, SogdiaCosmetics collection, address reserve, uint16 commissionBps, address initialOwner) Ownable(initialOwner) {
        if (address(paymentToken).code.length == 0 || address(collection).code.length == 0 || reserve == address(0) || reserve == address(this) || commissionBps >= 10000) revert InvalidInput();
        token = paymentToken; cosmetics = collection; rewardReserve = reserve; feeBps = commissionBps;
    }
    /// Terms for an existing product, set once.
    function createOffer(uint256 item, uint256 price, uint64 start, uint64 end) external onlyOwner {
        (bool exists,,,) = cosmetics.product(item);
        if (!exists || price == 0 || offers[item].price != 0 || (end != 0 && (end <= start || end <= block.timestamp))) revert InvalidInput();
        offers[item] = Offer(price, start, end); emit OfferCreated(item, price, start, end);
    }
    function buyPrimary(uint256 item, uint256 amount, uint256 expectedTotal) external nonReentrant {
        Offer memory o = offers[item];
        if (o.price == 0 || amount == 0 || block.timestamp < o.start || (o.end != 0 && block.timestamp >= o.end)) revert Unavailable();
        uint256 total = o.price * amount;
        if (total != expectedTotal) revert InvalidInput();
        _pay(msg.sender, rewardReserve, total);
        cosmetics.mintPurchase(msg.sender, item, amount);
        emit Purchased(msg.sender, item, amount, total);
    }
    function _pay(address from, address to, uint256 amount) private {
        if (from == to) revert InvalidInput();
        uint256 beforeFrom = token.balanceOf(from); uint256 beforeTo = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount);
        if (token.balanceOf(from) != beforeFrom - amount || token.balanceOf(to) != beforeTo + amount) revert UnsupportedTransfer();
    }
}
