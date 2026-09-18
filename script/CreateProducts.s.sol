// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// Opens a catalogue on chain: one `createProduct` on the collection and one `createOffer` on the
/// marketplace for every item in a file. Both are owner-only and both are once-per-item, so this is
/// the step that turns a reviewed price list into a store that can sell.
///
/// The file is four parallel arrays, so that what is signed is exactly what a reviewer read:
///
///     { "ids": [60000, ...], "caps": [50, ...], "prices": [24000, ...],
///       "metadata": ["https://assets.sogdia.gg/nft/v2/60000.json", ...] }
///
/// `caps` is the supply cap, 0 for unlimited, and is immutable once the product exists. `prices` are
/// WHOLE tokens; the script multiplies by the payment token's own `decimals()` rather than taking a
/// number nobody can check by eye. `metadata` is the product's URI and is immutable too.
///
/// The file goes in `products/`, which is the only directory the project may read (`foundry.toml`
/// fs_permissions) and is not committed.
///
///     CHAIN_ID=46630 PAYMENT_TOKEN=0x… \
///     COSMETICS=0x… MARKETPLACE=0x… PRODUCTS=products/mall.json \
///     forge script script/CreateProducts.s.sol:CreateProducts --rpc-url <url>
///
/// That is a dry run: it simulates everything and writes nothing. Add `--broadcast` with the owner's
/// key (`--keystore`/`--account`) to send. OFFER_START and OFFER_END are unix seconds, defaulting to
/// 0 and 0, where 0 means the sale has no end (`SogdiaMarketplace.createOffer`).
///
/// Set CHAIN_ID and PAYMENT_TOKEN explicitly. A rerun accepts only identical existing terms.
interface ScriptVm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonUintArray(string calldata json, string calldata key) external pure returns (uint256[] memory);
    function parseJsonStringArray(string calldata json, string calldata key) external pure returns (string[] memory);
    function envUint(string calldata name) external view returns (uint256);
    function envAddress(string calldata name) external view returns (address);
    function envString(string calldata name) external view returns (string memory);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
}

contract CreateProducts {
    ScriptVm private constant VM = ScriptVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    error LengthMismatch();
    error InvalidCatalog();
    error ExistingTermsDiffer(uint256 item);

    function run() external {
        SogdiaCosmetics collection = SogdiaCosmetics(VM.envAddress("COSMETICS"));
        SogdiaMarketplace market = SogdiaMarketplace(VM.envAddress("MARKETPLACE"));
        uint256 rawStart = VM.envOr("OFFER_START", uint256(0));
        uint256 rawEnd = VM.envOr("OFFER_END", uint256(0));
        if (block.chainid != VM.envUint("CHAIN_ID") || address(market.token()) != VM.envAddress("PAYMENT_TOKEN")
            || rawStart > type(uint64).max || rawEnd > type(uint64).max) revert InvalidCatalog();
        string memory file = VM.readFile(VM.envString("PRODUCTS"));
        uint64 start = uint64(rawStart); uint64 end = uint64(rawEnd);
        uint256[] memory ids = VM.parseJsonUintArray(file, ".ids");
        uint256[] memory caps = VM.parseJsonUintArray(file, ".caps");
        string[] memory metadata = VM.parseJsonStringArray(file, ".metadata");
        uint256[] memory prices = VM.parseJsonUintArray(file, ".prices");
        // Validate the entire file before recording any broadcast transaction.
        validate(collection, market, ids, caps, metadata, prices, start, end);
        VM.startBroadcast();
        open(
            collection,
            market,
            ids, caps, metadata, prices,
            start,
            end
        );
        VM.stopBroadcast();
    }

    /// Public so a test can drive it with arrays instead of a file and a broadcast.
    function open(
        SogdiaCosmetics collection,
        SogdiaMarketplace market,
        uint256[] memory ids,
        uint256[] memory caps,
        string[] memory metadata,
        uint256[] memory prices,
        uint64 start,
        uint64 end
    ) public {
        validate(collection, market, ids, caps, metadata, prices, start, end);
        uint256 unit = 10 ** IERC20Metadata(address(market.token())).decimals();
        for (uint256 i = 0; i < ids.length; i++) {
            (bool exists,,,) = collection.product(ids[i]);
            if (!exists) collection.createProduct(ids[i], caps[i], metadata[i]);
            (uint256 offered,,) = market.offers(ids[i]);
            if (offered == 0) market.createOffer(ids[i], prices[i] * unit, start, end);
        }
    }
    function validate(SogdiaCosmetics collection, SogdiaMarketplace market, uint256[] memory ids,
        uint256[] memory caps, string[] memory metadata, uint256[] memory prices, uint64 start, uint64 end) public view {
        if (ids.length != caps.length || ids.length != metadata.length || ids.length != prices.length) revert LengthMismatch();
        if (ids.length == 0 || address(market.cosmetics()) != address(collection)
            || collection.marketplace() != address(market) || collection.owner() != market.owner()) revert InvalidCatalog();
        uint8 decimals = IERC20Metadata(address(market.token())).decimals();
        if (decimals > 77 || (end != 0 && end <= start)) revert InvalidCatalog();
        uint256 unit = 10 ** decimals;
        for (uint256 i; i < ids.length; ++i) {
            if (ids[i] == 0 || bytes(metadata[i]).length == 0 || prices[i] == 0 || prices[i] > type(uint256).max / unit) revert InvalidCatalog();
            for (uint256 j; j < i; ++j) if (ids[j] == ids[i]) revert InvalidCatalog();
            {
            (bool exists,uint256 cap,,string memory uri) = collection.product(ids[i]);
            if (exists && (cap != caps[i] || keccak256(bytes(uri)) != keccak256(bytes(metadata[i])))) revert ExistingTermsDiffer(ids[i]);
            }
            (uint256 price,uint64 previousStart,uint64 previousEnd) = market.offers(ids[i]);
            if (price != 0 && (price != prices[i] * unit || previousStart != start || previousEnd != end)) revert ExistingTermsDiffer(ids[i]);
            if (price == 0 && end != 0 && end <= block.timestamp) revert InvalidCatalog();
        }
    }

}
