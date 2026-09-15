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
    function testFuzzConservation(uint8 raw) public {
        uint256 amount=uint256(raw)%3+1;uint256 id=listing(amount);vm.prank(B);m.buyListing(id,amount,amount*200);
        require(c.totalSupply(60000)==amount&&c.balanceOf(B,60000)==amount&&c.balanceOf(address(m),60000)==0);
        require(t.balanceOf(A)+t.balanceOf(B)+t.balanceOf(R)==20000);
    }
}
