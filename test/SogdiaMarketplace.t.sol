// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {TestToken} from "./TestToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
interface MarketVm { function warp(uint256) external; function prank(address) external; function expectRevert() external; }
contract MarketTaxToken is ERC20 {
    constructor() ERC20("Adversarial test token", "BAD") { _mint(msg.sender,1000); }
    function transferFrom(address f,address t,uint256 n) public override returns(bool) { return super.transferFrom(f,t,n-1); }
}
contract RejectingBuyer {
    function buy(TestToken t,SogdiaMarketplace m) external { t.approve(address(m),1000); m.buyPrimary(60000,1,100); }
}
contract ReenteringBuyer {
    SogdiaMarketplace market; bool public blocked;
    function buy(TestToken t,SogdiaMarketplace m) external { market=m;t.approve(address(m),1000);m.buyPrimary(60000,1,100); }
    function onERC1155Received(address,address,uint256,uint256,bytes calldata) external returns(bytes4) {
        try market.buyPrimary(60000,1,100) { revert("nested purchase admitted"); } catch { blocked=true; }
        return this.onERC1155Received.selector;
    }
}
contract SogdiaMarketplaceTest {
    MarketVm constant vm=MarketVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant A=address(0xA11CE); address constant B=address(0xB0B); address constant R=address(0x1234);
    TestToken t; SogdiaCosmetics c; SogdiaMarketplace m;
    function setUp() public {
        vm.warp(1000); t=new TestToken(100000); c=new SogdiaCosmetics(address(this));
        m=new SogdiaMarketplace(t,c,R,250,address(this)); c.bindMarketplace(address(m));
        c.createProduct(60000,3,"ipfs://synthetic-fixture/hat.json"); m.createOffer(60000,100,1000,2000);
        t.transfer(A,10000); t.transfer(B,10000); vm.prank(A);t.approve(address(m),10000); vm.prank(B);t.approve(address(m),10000);
    }
    function buy(address who,uint256 n) private { vm.prank(who);m.buyPrimary(60000,n,n*100); }
    function listing(uint256 n) private returns(uint256) { buy(A,n);vm.prank(A);c.setApprovalForAll(address(m),true);vm.prank(A);return m.list(60000,n,200,1500); }
    function testLimitedSupplyAndSoldOutRollback() public {
        buy(A,2);buy(B,1);uint256 before=t.balanceOf(B);vm.expectRevert();buy(B,1);
        require(c.totalSupply(60000)==3&&t.balanceOf(B)==before&&t.balanceOf(R)==300);
        (,uint256 cap,uint256 minted,)=c.product(60000);require(cap==3&&minted==3);
    }
    function testNoOwnerMintCapMetadataEditOrMarketReplacement() public {
        vm.expectRevert();c.mintPurchase(A,60000,1);vm.expectRevert();c.createProduct(60000,500,"changed");vm.expectRevert();c.bindMarketplace(address(m));
        vm.prank(A);vm.expectRevert();c.createProduct(60001,1,"x");
    }
    function testUncappedProductIsExplicitAndSeparate() public {
        c.createProduct(60001,0,"ipfs://synthetic-fixture/standard.json");m.createOffer(60001,1,1000,0);
        vm.prank(A);m.buyPrimary(60001,10,10);require(c.totalSupply(60001)==10&&c.totalSupply(60000)==0);
    }
    function testEscrowPartialSaleAndCancellationConserveSupply() public {
        uint256 id=listing(2);require(c.balanceOf(A,60000)==0&&c.balanceOf(address(m),60000)==2);
        vm.prank(B);m.buyListing(id,1,200);require(c.balanceOf(B,60000)==1&&t.balanceOf(A)==9995&&t.balanceOf(R)==205);
        vm.prank(A);m.cancel(id);require(c.balanceOf(A,60000)==1&&c.balanceOf(address(m),60000)==0&&c.totalSupply(60000)==2);
        vm.prank(B);vm.expectRevert();m.buyListing(id,1,200);
    }
    function testOnlySellerCanCancelAndCannotDoubleSell() public {
        uint256 id=listing(1);vm.prank(B);vm.expectRevert();m.cancel(id);
        vm.prank(B);m.buyListing(id,1,200);vm.prank(B);vm.expectRevert();m.buyListing(id,1,200);vm.prank(A);vm.expectRevert();m.cancel(id);
    }
    function testSelfTradeWrongPriceAndExpiredListingFail() public {
        uint256 id=listing(1);vm.prank(A);vm.expectRevert();m.buyListing(id,1,200);
        vm.prank(B);vm.expectRevert();m.buyListing(id,1,199);vm.warp(1500);vm.prank(B);vm.expectRevert();m.buyListing(id,1,200);
        vm.prank(A);m.cancel(id);require(c.balanceOf(A,60000)==1);
    }
    function testNoUnsolicitedEscrowTransfer() public {
        buy(A,1);vm.prank(A);vm.expectRevert();c.safeTransferFrom(A,address(m),60000,1,"");require(c.balanceOf(A,60000)==1);
    }
    function testPaymentFailureLeavesStockAndEscrowUnchanged() public {
        vm.prank(B);t.approve(address(m),0);vm.expectRevert();buy(B,1);require(c.totalSupply(60000)==0);
        uint256 id=listing(1);vm.prank(B);vm.expectRevert();m.buyListing(id,1,200);(,,uint256 remaining,,)=m.listings(id);require(remaining==1&&c.balanceOf(address(m),60000)==1);
    }
    function testReceiverRejectionRollsBackPaymentAndMint() public {
        RejectingBuyer b=new RejectingBuyer();t.transfer(address(b),1000);vm.expectRevert();b.buy(t,m);require(c.totalSupply(60000)==0&&t.balanceOf(address(b))==1000&&t.balanceOf(R)==0);
    }
    function testReceiverCannotReenterPurchase() public {
        ReenteringBuyer b=new ReenteringBuyer();t.transfer(address(b),1000);b.buy(t,m);
        require(b.blocked()&&c.balanceOf(address(b),60000)==1&&c.totalSupply(60000)==1&&t.balanceOf(R)==100&&t.balanceOf(address(b))==900);
    }
    function testTaxedPaymentRejectedAtomically() public {
        MarketTaxToken bad=new MarketTaxToken();SogdiaCosmetics cc=new SogdiaCosmetics(address(this));SogdiaMarketplace mm=new SogdiaMarketplace(bad,cc,R,250,address(this));cc.bindMarketplace(address(mm));cc.createProduct(1,1,"x");mm.createOffer(1,100,1000,0);
        bad.transfer(A,200);vm.prank(A);bad.approve(address(mm),200);vm.prank(A);vm.expectRevert();mm.buyPrimary(1,1,100);require(cc.totalSupply(1)==0&&bad.balanceOf(A)==200&&bad.balanceOf(R)==0);
    }
    function testPrimaryScheduleAndExactQuote() public {
        vm.prank(A);vm.expectRevert();m.buyPrimary(60000,1,99);vm.warp(999);vm.expectRevert();buy(A,1);vm.warp(2000);vm.expectRevert();buy(A,1);
        vm.expectRevert();m.createOffer(60000,101,1000,0);
    }
    // owner price update; a quote made before the change reverts without taking payment.
    function testOwnerUpdatesOfferAndStaleQuoteReverts() public {
        vm.prank(A);vm.expectRevert();m.updateOffer(60000,150,1000,2000);
        vm.expectRevert();m.updateOffer(60001,150,1000,2000);
        vm.expectRevert();m.updateOffer(60000,0,1000,2000);
        vm.expectRevert();m.updateOffer(60000,150,1500,1500);
        m.updateOffer(60000,150,1000,0);
        uint256 before=t.balanceOf(A);vm.prank(A);vm.expectRevert();m.buyPrimary(60000,1,100);
        require(t.balanceOf(A)==before&&c.totalSupply(60000)==0);
        vm.prank(A);m.buyPrimary(60000,1,150);require(t.balanceOf(R)==150);
        (,uint256 cap,,)=c.product(60000);require(cap==3);
        vm.warp(1200);m.updateOffer(60000,150,1000,1100);vm.prank(A);vm.expectRevert();m.buyPrimary(60000,1,150);
    }
    // pause stops primary sales, new listings and listing purchases; cancel stays open.
    function testPauseBlocksSalesButNeverCancel() public {
        uint256 id=listing(1);buy(B,1);vm.prank(B);c.setApprovalForAll(address(m),true);
        vm.prank(A);vm.expectRevert();m.pause();
        m.pause();
        vm.prank(A);vm.expectRevert();m.buyPrimary(60000,1,100);
        vm.prank(B);vm.expectRevert();m.list(60000,1,200,1500);
        vm.prank(B);vm.expectRevert();m.buyListing(id,1,200);
        vm.prank(A);m.cancel(id);require(c.balanceOf(A,60000)==1&&c.balanceOf(address(m),60000)==0);
        m.unpause();buy(A,1);require(c.totalSupply(60000)==3);
    }
    // no renounce; ownership moves only when the new owner (a Safe in production) accepts.
    function testOwnershipCannotBeRenouncedAndNeedsAcceptance() public {
        address safe=address(0x5AFE);
        vm.expectRevert();m.renounceOwnership();
        m.transferOwnership(safe);require(m.owner()==address(this)&&m.pendingOwner()==safe);
        vm.prank(A);vm.expectRevert();m.acceptOwnership();
        vm.prank(safe);m.acceptOwnership();require(m.owner()==safe);
        vm.expectRevert();m.pause();
        vm.prank(safe);m.pause();require(m.paused());
    }
    function testCollectionTitleAndExternalTransfer() public {
        require(keccak256(bytes(c.name())) == keccak256("Sogdia"));
        require(keccak256(bytes(c.symbol())) == keccak256("SOGDIA"));
        vm.prank(A); t.approve(address(m), 100);
        vm.prank(A); m.buyPrimary(60000, 1, 100);
        vm.prank(A); c.safeTransferFrom(A, B, 60000, 1, "");
        require(c.balanceOf(A, 60000) == 0 && c.balanceOf(B, 60000) == 1);
    }

    // External marketplaces: ERC-2981 royalty is owner-set, capped, and independent of the marketplace fee.
    function testRoyaltyIsOwnerSetCappedAndSeparateFromMarketFee() public {
        (address none,uint256 zero)=c.royaltyInfo(60000,10000);
        require(none==address(0)&&zero==0);
        require(c.supportsInterface(0x2a55205a)&&c.supportsInterface(0xd9b67a26));
        address wallet=address(0x7A7);
        vm.prank(A);vm.expectRevert();c.setRoyalty(wallet,500);
        vm.expectRevert();c.setRoyalty(address(0),500);
        vm.expectRevert();c.setRoyalty(wallet,1001);
        c.setRoyalty(wallet,500);
        (address receiver,uint256 amount)=c.royaltyInfo(60000,10000);
        require(receiver==wallet&&amount==500);
        (,uint256 large)=c.royaltyInfo(1,39800*10**18);
        require(large==39800*10**18*500/10000);
        c.setRoyalty(R,1000);
        (receiver,amount)=c.royaltyInfo(60000,10000);
        require(receiver==R&&amount==1000);
        uint256 id=listing(1);vm.prank(B);m.buyListing(id,1,200);
        require(t.balanceOf(A)==10095&&t.balanceOf(R)==105);
    }
    // The collection's own title, for a marketplace that has no ERC-1155 field to read it from. What
    // the title says is a branding decision and is not pinned here; that both are answered is not.
    function testCollectionNameAndSymbol() public view {
        require(bytes(c.name()).length>0);
        require(bytes(c.symbol()).length>0);
    }

    // ERC-7572 collection metadata: owner-only, non-empty.
    function testContractURIIsOwnerOnly() public {
        require(bytes(c.contractURI()).length==0);
        c.setContractURI("https://assets.sogdia.gg/nft/collection.json");
        require(keccak256(bytes(c.contractURI()))==keccak256("https://assets.sogdia.gg/nft/collection.json"));
        vm.prank(A);vm.expectRevert();c.setContractURI("https://evil.example/x.json");
        vm.expectRevert();c.setContractURI("");
    }
    function testFuzzConservation(uint8 raw) public {
        uint256 amount=uint256(raw)%3+1;uint256 id=listing(amount);vm.prank(B);m.buyListing(id,amount,amount*200);
        require(c.totalSupply(60000)==amount&&c.balanceOf(B,60000)==amount&&c.balanceOf(address(m),60000)==0);
        require(t.balanceOf(A)+t.balanceOf(B)+t.balanceOf(R)==20000);
    }
}
