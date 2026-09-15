// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @notice Funded Sogdia player rewards, paid out through Merkle claims.
/// @dev The publisher is trusted for gameplay eligibility and root totals. A Merkle proof
/// proves membership, NOT that the publisher correctly summed/selected every leaf.
/// Non-upgradeable, immutable token, no withdrawal. Plain, non-rebasing,
/// non-taxed ERC20 only. Launch-token compatibility must be tested before deployment.
contract SogdiaRewards is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DOMAIN = keccak256("SogdiaRewards.v1");
    IERC20 public immutable token;
    uint256 public reserved;

    struct Period {
        uint64 start;
        uint64 end;
        bool opened;
        bool finalized;
        bytes32 policyHash;
        bytes32 root;
        uint256 goldBudget;
        uint256 caravanBudget;
        uint256 goldRemaining;
        uint256 caravanRemaining;
    }
    mapping(bytes32 => Period) public periods;
    mapping(bytes32 => mapping(uint256 => bool)) public claimed;

    error InvalidInput();
    error InvalidPeriod();
    error InsufficientReserve();
    error InvalidProof();
    error AlreadyClaimed();
    error UnsupportedTransfer();

    event Funded(address indexed sender, uint256 amount);
    event PeriodOpened(
        bytes32 indexed period, uint64 start, uint64 end, uint256 goldBudget, uint256 caravanBudget, bytes32 policyHash
    );
    event PeriodFinalized(
        bytes32 indexed period, bytes32 root, uint256 goldTotal, uint256 caravanTotal, uint256 released
    );
    event Claimed(
        bytes32 indexed period, uint256 indexed index, address indexed recipient, uint8 channel, uint256 amount
    );

    constructor(IERC20 rewardToken, address initialOwner) Ownable(initialOwner) {
        if (address(rewardToken).code.length == 0) revert InvalidInput();
        token = rewardToken;
    }

    function available() public view returns (uint256) {
        uint256 balance = token.balanceOf(address(this));
        if (balance < reserved) revert InsufficientReserve();
        return balance - reserved;
    }

    function fund(uint256 amount) external nonReentrant {
        if (amount == 0) revert InvalidInput();
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        if (token.balanceOf(address(this)) != beforeBalance + amount) revert UnsupportedTransfer();
        emit Funded(msg.sender, amount);
    }

    function openPeriod(
        bytes32 id,
        uint64 start,
        uint64 end,
        uint256 goldBudget,
        uint256 caravanBudget,
        bytes32 policyHash
    ) external onlyOwner nonReentrant {
        if (id == bytes32(0) || policyHash == bytes32(0) || start < block.timestamp || end <= start) {
            revert InvalidInput();
        }
        if (periods[id].opened) revert InvalidPeriod();
        uint256 budget = goldBudget + caravanBudget;
        if (budget == 0) revert InvalidInput();
        uint256 free = available();
        if (budget > free) revert InsufficientReserve();
        reserved += budget;
        periods[id] = Period(start, end, true, false, policyHash, bytes32(0), goldBudget, caravanBudget, 0, 0);
        emit PeriodOpened(id, start, end, goldBudget, caravanBudget, policyHash);
    }

    function finalizePeriod(bytes32 id, bytes32 root, uint256 goldTotal, uint256 caravanTotal)
        external
        onlyOwner
        nonReentrant
    {
        Period storage p = periods[id];
        if (!p.opened || p.finalized || block.timestamp < p.end) revert InvalidPeriod();
        if (goldTotal > p.goldBudget || caravanTotal > p.caravanBudget) revert InvalidInput();
        uint256 total = goldTotal + caravanTotal;
        if ((total == 0) != (root == bytes32(0))) revert InvalidInput();
        p.finalized = true;
        p.root = root;
        p.goldRemaining = goldTotal;
        p.caravanRemaining = caravanTotal;
        uint256 released = p.goldBudget + p.caravanBudget - total;
        reserved -= released;
        emit PeriodFinalized(id, root, goldTotal, caravanTotal, released);
    }

    /// StandardMerkleTree double-hashed ABI leaf. Domain binds chain, deployment and token.
    /// channel: 0 = Gold conversion; 1 = caravan. Index is unique across both channels.
    function leaf(bytes32 id, uint256 index, address recipient, uint8 channel, uint256 amount)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            bytes.concat(
                keccak256(
                    abi.encode(
                        DOMAIN, block.chainid, address(this), address(token), id, index, recipient, channel, amount
                    )
                )
            )
        );
    }

    /// Permissionless relay, fixed payout destination; no signature or redirect parameter.
    function claim(
        bytes32 id,
        uint256 index,
        address recipient,
        uint8 channel,
        uint256 amount,
        bytes32[] calldata proof
    ) external nonReentrant {
        Period storage p = periods[id];
        if (!p.finalized) revert InvalidPeriod();
        if (recipient == address(0) || recipient == address(this) || amount == 0 || channel > 1) {
            revert InvalidInput();
        }
        if (claimed[id][index]) revert AlreadyClaimed();
        if (!MerkleProof.verifyCalldata(proof, p.root, leaf(id, index, recipient, channel, amount))) {
            revert InvalidProof();
        }
        if (channel == 0) {
            if (amount > p.goldRemaining) revert InsufficientReserve();
            p.goldRemaining -= amount;
        } else {
            if (amount > p.caravanRemaining) revert InsufficientReserve();
            p.caravanRemaining -= amount;
        }
        claimed[id][index] = true;
        reserved -= amount;
        uint256 beforeSender = token.balanceOf(address(this));
        uint256 beforeRecipient = token.balanceOf(recipient);
        token.safeTransfer(recipient, amount);
        if (
            token.balanceOf(address(this)) != beforeSender - amount
                || token.balanceOf(recipient) != beforeRecipient + amount
        ) revert UnsupportedTransfer();
        emit Claimed(id, index, recipient, channel, amount);
    }

    /// A pending period must not become impossible to finalize through accidental renunciation.
    function renounceOwnership() public view override onlyOwner {
        revert InvalidInput();
    }
}
