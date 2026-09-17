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
///     COSMETICS=0x… MARKETPLACE=0x… PRODUCTS=/path/products.json \
///     forge script script/CreateProducts.s.sol:CreateProducts --rpc-url <url>
///
/// That is a dry run: it simulates everything and writes nothing. Add `--broadcast` with the owner's
/// key (`--keystore`/`--account`) to send. OFFER_START and OFFER_END are unix seconds, defaulting to
/// "now" and 0, where 0 means the sale has no end (`SogdiaMarketplace.createOffer`).
///
/// A rerun skips what is already there, so a run that stops halfway can simply be repeated.
interface ScriptVm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function readFile(string calldata path) external view returns (string memory);
    function parseJsonUintArray(string calldata json, string calldata key) external pure returns (uint256[] memory);
    function parseJsonStringArray(string calldata json, string calldata key) external pure returns (string[] memory);
    function envAddress(string calldata name) external view returns (address);
    function envString(string calldata name) external view returns (string memory);
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
}

contract CreateProducts {
    ScriptVm private constant VM = ScriptVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    error LengthMismatch();

    function run() external {
        SogdiaCosmetics collection = SogdiaCosmetics(VM.envAddress("COSMETICS"));
        SogdiaMarketplace market = SogdiaMarketplace(VM.envAddress("MARKETPLACE"));
        string memory file = VM.readFile(VM.envString("PRODUCTS"));
        uint64 start = uint64(VM.envOr("OFFER_START", block.timestamp));
        uint64 end = uint64(VM.envOr("OFFER_END", uint256(0)));
        VM.startBroadcast();
        open(
            collection,
            market,
            VM.parseJsonUintArray(file, ".ids"),
            VM.parseJsonUintArray(file, ".caps"),
            VM.parseJsonStringArray(file, ".metadata"),
            VM.parseJsonUintArray(file, ".prices"),
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
        if (ids.length != caps.length || ids.length != metadata.length || ids.length != prices.length) revert LengthMismatch();
        uint256 unit = 10 ** IERC20Metadata(address(market.token())).decimals();
        for (uint256 i = 0; i < ids.length; i++) {
            (bool exists,,,) = collection.product(ids[i]);
            if (!exists) collection.createProduct(ids[i], caps[i], metadata[i]);
            (uint256 offered,,) = market.offers(ids[i]);
            if (offered == 0) market.createOffer(ids[i], prices[i] * unit, start, end);
        }
    }
}
