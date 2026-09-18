// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaMarketplace} from "./SogdiaMarketplace.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// One-way redemption of store packages into game inventory. Redeemed NFTs stay
/// locked forever: no owner withdrawal or second transferable copy of a consumable.
contract SogdiaMallDelivery is ERC165, IERC1155Receiver, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;
    SogdiaMarketplace public immutable market;
    bytes32 public immutable catalogHash;
    uint256 public nextDelivery = 1;
    address public immutable authorizationSigner;
    mapping(bytes32 => bool) public usedAuthorizations;
    bytes32 private constant AUTHORIZATION_TYPEHASH = keccak256("DeliveryAuthorization(address buyer,uint256 item,uint256 amount,uint64 character,uint8 action,uint256 expectedTotal,bytes32 nonce,uint64 deadline)");
    error InvalidAuthorization();
    mapping(uint256 => bool) public supported;
    bool private receiving;
    address private expectedFrom;
    uint256 private expectedItem;
    uint256 private expectedAmount;
    error InvalidDelivery();
    event DeliveryQueued(uint256 indexed delivery, address indexed buyer, uint256 indexed item, uint256 amount, uint64 character);
    constructor(SogdiaMarketplace marketplace, bytes32 reviewedCatalogHash, uint256[] memory productIds, address signer) EIP712("SogdiaMallDelivery", "2") {
        if (signer == address(0) || address(marketplace).code.length == 0 || reviewedCatalogHash == bytes32(0)) revert InvalidDelivery();
        market = marketplace; catalogHash = reviewedCatalogHash; authorizationSigner = signer;
        if (productIds.length == 0) revert InvalidDelivery();
        for (uint256 i; i < productIds.length; ++i) {
            if (productIds[i] == 0 || supported[productIds[i]]) revert InvalidDelivery();
            supported[productIds[i]] = true;
        }
    }
    /// Buy and surrender the package in the same transaction. Inventory delivery
    /// waits for finality; a full bag retains the durable claim for later retry.
    function buyAndDeliver(uint256 item, uint256 amount, uint256 expectedTotal, uint64 character, bytes32 nonce, uint64 deadline, bytes calldata signature) external nonReentrant {
        _authorize(item, amount, character, 0, expectedTotal, nonce, deadline, signature);
        _expect(address(0), item, amount, character);
        IERC20 token = market.token();
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), expectedTotal);
        if (token.balanceOf(address(this)) != beforeBalance + expectedTotal) revert InvalidDelivery();
        token.forceApprove(address(market), expectedTotal);
        market.buyPrimary(item, amount, expectedTotal);
        token.forceApprove(address(market), 0);
        if (receiving || token.balanceOf(address(this)) != beforeBalance) revert InvalidDelivery();
        emit DeliveryQueued(nextDelivery++, msg.sender, item, amount, character);
    }
    /// Also redeem packages previously purchased or obtained on a player market.
    function deliverOwned(uint256 item, uint256 amount, uint64 character, bytes32 nonce, uint64 deadline, bytes calldata signature) external nonReentrant {
        _authorize(item, amount, character, 1, 0, nonce, deadline, signature);
        _expect(msg.sender, item, amount, character);
        market.cosmetics().safeTransferFrom(msg.sender, address(this), item, amount, "");
        if (receiving) revert InvalidDelivery();
        emit DeliveryQueued(nextDelivery++, msg.sender, item, amount, character);
    }
    /// Server checks character ownership before signing. Domain binds chain and this deployment.
    /// Action 0 buys and delivers; action 1 redeems an already-owned item.
    function authorizationDigest(address buyer, uint256 item, uint256 amount, uint64 character,
        uint8 action, uint256 expectedTotal, bytes32 nonce, uint64 deadline) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(AUTHORIZATION_TYPEHASH, buyer, item, amount,
            character, action, expectedTotal, nonce, deadline)));
    }
    function _authorize(uint256 item, uint256 amount, uint64 character, uint8 action,
        uint256 expectedTotal, bytes32 nonce, uint64 deadline, bytes calldata signature) private {
        if (nonce == bytes32(0) || usedAuthorizations[nonce] || deadline < block.timestamp
            || deadline > block.timestamp + 300) revert InvalidAuthorization();
        if (ECDSA.recover(authorizationDigest(msg.sender, item, amount, character, action,
            expectedTotal, nonce, deadline), signature) != authorizationSigner) revert InvalidAuthorization();
        // Consumed before external calls; a reverted payment/delivery rolls this back too.
        usedAuthorizations[nonce] = true;
    }
    function _expect(address from, uint256 item, uint256 amount, uint64 character) private {
        if (!supported[item] || amount == 0 || amount > type(uint16).max || character == 0) revert InvalidDelivery();
        receiving = true; expectedFrom = from; expectedItem = item; expectedAmount = amount;
    }
    function onERC1155Received(address, address from, uint256 item, uint256 amount, bytes calldata) external returns (bytes4) {
        if (msg.sender != address(market.cosmetics()) || !receiving || from != expectedFrom || item != expectedItem || amount != expectedAmount) revert InvalidDelivery();
        receiving = false;
        return this.onERC1155Received.selector;
    }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) { revert InvalidDelivery(); }
    function supportsInterface(bytes4 id) public view override(ERC165, IERC165) returns (bool) {
        return id == type(IERC1155Receiver).interfaceId || super.supportsInterface(id);
    }
}
