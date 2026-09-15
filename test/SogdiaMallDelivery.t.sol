// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaMallDelivery} from "../src/SogdiaMallDelivery.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {TestToken} from "./TestToken.sol";
interface DeliveryVm { function prank(address) external; function expectRevert() external; }
contract SogdiaMallDeliveryTest {
    DeliveryVm constant vm=DeliveryVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant A=address(0xA11CE);address constant R=address(0x1234);
    TestToken t; SogdiaCosmetics c; SogdiaMarketplace m; SogdiaMallDelivery d;
    function setUp() public {
        t=new TestToken(100000); c=new SogdiaCosmetics(address(this));
        m=new SogdiaMarketplace(t,c,R,250,address(this));c.bindMarketplace(address(m));
        c.createProduct(42,3,"synthetic-package");m.createOffer(42,100,0,0);
        uint256[] memory ids=new uint256[](1);ids[0]=42;
        d=new SogdiaMallDelivery(m,keccak256("synthetic-catalog"),ids);
        t.transfer(A,1000);vm.prank(A);t.approve(address(d),1000);
    }
    function testPurchaseLocksNftAndPaysReserveOnce() public {
        vm.prank(A);d.buyAndDeliver(42,2,200,9011);
        require(c.balanceOf(A,42)==0 && c.balanceOf(address(d),42)==2 && t.balanceOf(R)==200);
        require(d.nextDelivery()==2 && t.allowance(address(d),address(m))==0);
        vm.prank(A);vm.expectRevert();c.safeTransferFrom(address(d),A,42,1,"");
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,2,200,9011);
        require(t.balanceOf(A)==800 && d.nextDelivery()==2);
    }
    function testRedeemOwnedOnceAndRejectUnsolicitedTransfer() public {
        vm.prank(A);t.approve(address(m),100);vm.prank(A);m.buyPrimary(42,1,100);
        vm.prank(A);vm.expectRevert();c.safeTransferFrom(A,address(d),42,1,"");
        vm.prank(A);c.setApprovalForAll(address(d),true);vm.prank(A);d.deliverOwned(42,1,9011);
        vm.prank(A);vm.expectRevert();d.deliverOwned(42,1,9011);
        require(c.balanceOf(address(d),42)==1 && d.nextDelivery()==2);
    }
    function testWrongQuoteCharacterAndProductDoNotTakePayment() public {
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,99,9011);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,0);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(43,1,100,9011);
        require(t.balanceOf(A)==1000 && c.totalSupply(42)==0);
    }
}
