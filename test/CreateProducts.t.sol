// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {CreateProducts} from "../script/CreateProducts.s.sol";
import {TestToken} from "./TestToken.sol";

/// The catalogue opener drives two owner-only, once-per-item calls over a whole price list, and a run
/// that stops halfway has to be safe to repeat. Both are checked here against a real pair of contracts;
/// the file reading and the broadcast are forge's, so the test hands it the arrays directly.
contract CreateProductsTest {
    TestToken private t;
    SogdiaCosmetics private c;
    SogdiaMarketplace private m;
    CreateProducts private opener;

    function setUp() public {
        opener = new CreateProducts();
        t = new TestToken(1_000_000e18);
        // The opener is the owner: it is what makes the owner-only calls when forge broadcasts them.
        c = new SogdiaCosmetics(address(opener));
        m = new SogdiaMarketplace(t, c, address(0xBEEF), 250, address(opener));
    }

    function lists(uint256 n) private pure returns (uint256[] memory ids, uint256[] memory caps, string[] memory uris, uint256[] memory prices) {
        ids = new uint256[](n); caps = new uint256[](n); uris = new string[](n); prices = new uint256[](n);
        for (uint256 i = 0; i < n; i++) { ids[i] = 60000 + i; caps[i] = 50 + i; uris[i] = "https://example.invalid/x.json"; prices[i] = 24000 + i; }
    }

    function testOpensEveryProductAndOffer() public {
        (uint256[] memory ids, uint256[] memory caps, string[] memory uris, uint256[] memory prices) = lists(3);
        opener.open(c, m, ids, caps, uris, prices, 1000, 0);
        for (uint256 i = 0; i < ids.length; i++) {
            (bool exists, uint256 cap,, string memory uri) = c.product(ids[i]);
            require(exists && cap == caps[i] && keccak256(bytes(uri)) == keccak256(bytes(uris[i])));
            // Whole tokens in the file, base units on chain: the token's own decimals, not a constant.
            (uint256 price, uint64 start, uint64 end) = m.offers(ids[i]);
            require(price == prices[i] * 10 ** t.decimals() && start == 1000 && end == 0);
        }
    }

    /// A rerun must not revert: `createProduct` and `createOffer` both reject a second call for an item.
    function testRerunSkipsWhatIsAlreadyThere() public {
        (uint256[] memory ids, uint256[] memory caps, string[] memory uris, uint256[] memory prices) = lists(2);
        opener.open(c, m, ids, caps, uris, prices, 1000, 0);
        opener.open(c, m, ids, caps, uris, prices, 1000, 0);
        (, uint256 cap,,) = c.product(ids[0]);
        (uint256 price,,) = m.offers(ids[0]);
        require(cap == caps[0] && price == prices[0] * 10 ** t.decimals());
    }

    /// Four parallel arrays only mean anything if they are the same length. The error is checked by
    /// selector, not just "it reverted": a ragged list reverts on the out-of-bounds read as well, so a
    /// bare try/catch here passes with the guard deleted — it was written that way first and did.
    function testRefusesRaggedLists() public {
        (uint256[] memory ids, uint256[] memory caps, string[] memory uris, uint256[] memory prices) = lists(2);
        uint256[] memory short = new uint256[](1);
        try opener.open(c, m, ids, short, uris, prices, 1000, 0) { require(false); }
        catch (bytes memory reason) { require(bytes4(reason) == CreateProducts.LengthMismatch.selector); }
        try opener.open(c, m, ids, caps, uris, short, 1000, 0) { require(false); }
        catch (bytes memory reason) { require(bytes4(reason) == CreateProducts.LengthMismatch.selector); }
        (bool exists,,,) = c.product(ids[0]);
        require(!exists);
    }
}
