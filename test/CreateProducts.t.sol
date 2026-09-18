// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {CreateProducts} from "../script/CreateProducts.s.sol";
import {TestToken} from "./TestToken.sol";

/// The catalogue opener drives two owner-only, once-per-item calls over a whole price list, and a run
/// that stops halfway has to be safe to repeat. Both are checked here against a real pair of contracts;
/// the file reading and the broadcast are forge's, so the test hands it the arrays directly.
interface CatalogVm { function prank(address) external; function expectRevert() external; function expectRevert(bytes4) external; function setEnv(string calldata,string calldata) external; function toString(address) external pure returns(string memory); function toString(uint256) external pure returns(string memory); }
contract CreateProductsTest {
    CatalogVm constant vm=CatalogVm(address(uint160(uint256(keccak256("hevm cheat code")))));
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
        vm.prank(address(opener)); c.bindMarketplace(address(m));
    }

    function testRunRejectsWrongNetworkTokenAndScheduleBeforeReadingOrBroadcasting() public {
        vm.setEnv("COSMETICS",vm.toString(address(c)));vm.setEnv("MARKETPLACE",vm.toString(address(m)));
        vm.setEnv("PAYMENT_TOKEN",vm.toString(address(t)));vm.setEnv("CHAIN_ID",vm.toString(block.chainid+1));
        vm.setEnv("OFFER_START","0");vm.setEnv("OFFER_END","0");vm.setEnv("PRODUCTS","products/does-not-exist.json");
        vm.expectRevert(CreateProducts.InvalidCatalog.selector);opener.run();
        vm.setEnv("CHAIN_ID",vm.toString(block.chainid));vm.setEnv("PAYMENT_TOKEN",vm.toString(address(0x1234)));
        vm.expectRevert(CreateProducts.InvalidCatalog.selector);opener.run();
        vm.setEnv("PAYMENT_TOKEN",vm.toString(address(t)));vm.setEnv("OFFER_START",vm.toString(uint256(type(uint64).max)+1));
        vm.expectRevert(CreateProducts.InvalidCatalog.selector);opener.run();vm.setEnv("OFFER_START","0");
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
    function testRerunRejectsChangedImmutableAndOfferTerms() public {
        (uint256[] memory ids,uint256[] memory caps,string[] memory uris,uint256[] memory prices)=lists(1);
        opener.open(c,m,ids,caps,uris,prices,1000,0);
        caps[0]++; vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,1000,0); caps[0]--;
        uris[0]="different"; vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,1000,0); uris[0]="https://example.invalid/x.json";
        prices[0]++; vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,1000,0); prices[0]--;
        vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,2000,0);
        vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,1000,3000);
    }
    function testInvalidLaterEntryDoesNotOpenEarlierProducts() public {
        (uint256[] memory ids,uint256[] memory caps,string[] memory uris,uint256[] memory prices)=lists(2);
        prices[1]=0; vm.expectRevert(); opener.open(c,m,ids,caps,uris,prices,1000,0);
        (bool exists,,,)=c.product(ids[0]); require(!exists);
        prices[1]=1;ids[1]=ids[0];vm.expectRevert();opener.open(c,m,ids,caps,uris,prices,1000,0);
    }
    function testWrongCollectionBindingAndEmptyCatalogFail() public {
        (uint256[] memory ids,uint256[] memory caps,string[] memory uris,uint256[] memory prices)=lists(1);
        SogdiaCosmetics other=new SogdiaCosmetics(address(opener));
        vm.expectRevert();opener.open(other,m,ids,caps,uris,prices,1000,0);
        (ids,caps,uris,prices)=lists(0);vm.expectRevert();opener.open(c,m,ids,caps,uris,prices,1000,0);
    }

}
