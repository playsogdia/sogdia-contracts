// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaMallDelivery} from "../src/SogdiaMallDelivery.sol";
import {SogdiaMarketplace} from "../src/SogdiaMarketplace.sol";
import {SogdiaCosmetics} from "../src/SogdiaCosmetics.sol";
import {TestToken} from "./TestToken.sol";
interface DeliveryVm {
    function prank(address) external;
    function expectRevert() external;
    function sign(uint256,bytes32) external returns(uint8,bytes32,bytes32);
    function addr(uint256) external returns(address);
    function warp(uint256) external;
    function chainId(uint256) external;
}
contract SogdiaMallDeliveryTest {
    DeliveryVm constant vm=DeliveryVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    // Synthetic local test signer only; never used by any deployment.
    uint256 constant SIGNER_KEY=123456;
    address constant A=address(0xA11CE);address constant R=address(0x1234);
    bytes32 constant NONCE=bytes32(uint256(1));
    TestToken t; SogdiaCosmetics c; SogdiaMarketplace m; SogdiaMallDelivery d;
    function setUp() public {
        t=new TestToken(100000); c=new SogdiaCosmetics(address(this));
        m=new SogdiaMarketplace(t,c,R,250,address(this));c.bindMarketplace(address(m));
        c.createProduct(42,3,"synthetic-package");m.createOffer(42,100,0,0);
        uint256[] memory ids=new uint256[](1);ids[0]=42;
        d=new SogdiaMallDelivery(m,keccak256("synthetic-catalog"),ids,vm.addr(SIGNER_KEY));
        t.transfer(A,1000);vm.prank(A);t.approve(address(d),1000);
    }
    function signature(uint256 item,uint256 amount,uint64 character,uint8 action,uint256 total,uint64 deadline) internal returns(bytes memory) {
        bytes32 digest=d.authorizationDigest(A,item,amount,character,action,total,NONCE,deadline);
        (uint8 v,bytes32 r,bytes32 s)=vm.sign(SIGNER_KEY,digest);
        return abi.encodePacked(r,s,v);
    }
    function deadline() internal view returns(uint64){return uint64(block.timestamp+120);}
    function testPurchaseLocksNftAndPaysReserveOnce() public {
        uint64 end=deadline();bytes memory sig=signature(42,2,9011,0,200,end);
        vm.prank(A);d.buyAndDeliver(42,2,200,9011,NONCE,end,sig);
        require(c.balanceOf(A,42)==0 && c.balanceOf(address(d),42)==2 && t.balanceOf(R)==200);
        require(d.nextDelivery()==2 && t.allowance(address(d),address(m))==0 && d.usedAuthorizations(NONCE));
        vm.prank(A);vm.expectRevert();c.safeTransferFrom(address(d),A,42,1,"");
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,2,200,9011,NONCE,end,sig);
        require(t.balanceOf(A)==800 && d.nextDelivery()==2);
    }
    function testRedeemOwnedOnceAndRejectUnsolicitedTransfer() public {
        vm.prank(A);t.approve(address(m),100);vm.prank(A);m.buyPrimary(42,1,100);
        vm.prank(A);vm.expectRevert();c.safeTransferFrom(A,address(d),42,1,"");
        vm.prank(A);c.setApprovalForAll(address(d),true);
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,1,0,end);
        vm.prank(A);d.deliverOwned(42,1,9011,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.deliverOwned(42,1,9011,NONCE,end,sig);
        require(c.balanceOf(address(d),42)==1 && d.nextDelivery()==2);
    }
    function testWrongQuoteCharacterAndProductDoNotTakePayment() public {
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,99,9011,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,type(uint64).max,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(43,1,100,9011,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,2,100,9011,NONCE,end,sig);
        require(t.balanceOf(A)==1000 && c.totalSupply(42)==0 && !d.usedAuthorizations(NONCE));
    }
    function testAuthorizationBindsBuyerActionNonceAndDeadline() public {
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,0,100,end);
        vm.prank(R);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.deliverOwned(42,1,9011,NONCE,end,sig);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,bytes32(uint256(2)),end,sig);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end+1,sig);
        require(!d.usedAuthorizations(NONCE) && t.balanceOf(A)==1000);
    }
    function testExpiredAndOverlongPermitsFail() public {
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,0,100,end);
        vm.warp(end+1);vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
        end=uint64(block.timestamp+301);sig=signature(42,1,9011,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
    }
    function testWrongSignerAndEmptySignatureFail() public {
        uint64 end=deadline();bytes32 digest=d.authorizationDigest(A,42,1,9011,0,100,NONCE,end);
        (uint8 v,bytes32 r,bytes32 s)=vm.sign(999,digest);bytes memory bad=abi.encodePacked(r,s,v);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,bad);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,"");
    }
    function testAuthorizationCannotCrossChainOrDeployment() public {
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,0,100,end);uint256 original=block.chainid;
        vm.chainId(original+1);vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);vm.chainId(original);
        uint256[] memory ids=new uint256[](1);ids[0]=42;
        SogdiaMallDelivery other=new SogdiaMallDelivery(m,keccak256("synthetic-catalog"),ids,vm.addr(SIGNER_KEY));
        vm.prank(A);t.approve(address(other),100);
        vm.prank(A);vm.expectRevert();other.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
    }
    function testPaymentFailureDoesNotConsumeAuthorization() public {
        uint64 end=deadline();bytes memory sig=signature(42,1,9011,0,100,end);
        vm.prank(A);t.approve(address(d),0);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
        require(!d.usedAuthorizations(NONCE));vm.prank(A);t.approve(address(d),100);
        vm.prank(A);d.buyAndDeliver(42,1,100,9011,NONCE,end,sig);
        require(d.usedAuthorizations(NONCE));
    }
    function testSignedInvalidPackageAmountAndCharacterFail() public {
        uint64 end=deadline();bytes memory sig=signature(43,1,9011,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(43,1,100,9011,NONCE,end,sig);
        sig=signature(42,0,9011,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,0,100,9011,NONCE,end,sig);
        sig=signature(42,65536,9011,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,65536,100,9011,NONCE,end,sig);
        sig=signature(42,1,0,0,100,end);
        vm.prank(A);vm.expectRevert();d.buyAndDeliver(42,1,100,0,NONCE,end,sig);
        require(!d.usedAuthorizations(NONCE) && t.balanceOf(A)==1000 && c.totalSupply(42)==0);
    }
    function testMissingSignerAndLegacyCallsFail() public {
        uint256[] memory ids=new uint256[](1);ids[0]=42;
        vm.expectRevert();new SogdiaMallDelivery(m,keccak256("synthetic-catalog"),ids,address(0));
        vm.prank(A);(bool ok,)=address(d).call(abi.encodeWithSignature("buyAndDeliver(uint256,uint256,uint256,uint64)",42,1,100,9011));
        require(!ok && t.balanceOf(A)==1000);
    }
}
