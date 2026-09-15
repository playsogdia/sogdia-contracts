// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {SogdiaRewards} from "../src/SogdiaRewards.sol";
import {TestToken} from "./TestToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface Vm {
    function warp(uint256) external;
    function chainId(uint256) external;
    function prank(address) external;
    function expectRevert() external;
}

contract AdversarialToken is ERC20 {
    bool public fail;
    bool public tax;
    address public callback;
    bytes public callbackData;
    bool public callbackSucceeded;

    constructor() ERC20("Adversarial fixture", "BAD") {
        _mint(msg.sender, 1000);
    }

    function configure(bool f, bool t, address c, bytes memory d) external {
        fail = f;
        tax = t;
        callback = c;
        callbackData = d;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (fail) return false;
        if (callback != address(0)) (callbackSucceeded,) = callback.call(callbackData);
        return super.transfer(to, tax ? value - 1 : value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (fail) return false;
        return super.transferFrom(from, to, tax ? value - 1 : value);
    }
}

contract SogdiaRewardsTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    TestToken t;
    SogdiaRewards r;
    bytes32 constant P = keccak256("test-period");
    bytes32 constant POLICY = keccak256("synthetic-policy");
    address constant A = address(0xA11CE);
    address constant B = address(0xB0B);

    function setUp() public {
        vm.warp(1000);
        vm.chainId(46630);
        t = new TestToken(1000);
        r = new SogdiaRewards(t, address(this));
        t.approve(address(r), 1000);
        r.fund(100);
    }

    function open() internal {
        r.openPeriod(P, 1000, 1100, 40, 60, POLICY);
    }

    function settle(uint8 channel, uint256 amount) internal {
        open();
        bytes32 root = r.leaf(P, 0, A, channel, amount);
        vm.warp(1100);
        r.finalizePeriod(P, root, channel == 0 ? amount : 0, channel == 1 ? amount : 0);
    }

    function proof() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function testFundingAndNoDoubleReservation() public {
        open();
        require(r.reserved() == 100 && r.available() == 0);
        vm.expectRevert();
        r.openPeriod(keccak256("next"), 1000, 1100, 1, 0, POLICY);
        require(r.reserved() == 100);
    }

    function testUnfundedAndUnauthorizedOpen() public {
        vm.expectRevert();
        r.openPeriod(P, 1000, 1100, 101, 0, POLICY);
        vm.prank(B);
        vm.expectRevert();
        r.openPeriod(P, 1000, 1100, 1, 0, POLICY);
    }

    function testPeriodValidationAndNoOverwrite() public {
        vm.expectRevert();
        r.openPeriod(P, 999, 1100, 1, 0, POLICY);
        vm.expectRevert();
        r.openPeriod(P, 1000, 1000, 1, 0, POLICY);
        vm.expectRevert();
        r.openPeriod(P, 1000, 1100, 0, 0, POLICY);
        open();
        vm.expectRevert();
        open();
    }

    function testFinalizeGatesAndChannelCaps() public {
        open();
        bytes32 root = r.leaf(P, 0, A, 0, 20);
        vm.expectRevert();
        r.finalizePeriod(P, root, 20, 0);
        vm.warp(1100);
        vm.prank(B);
        vm.expectRevert();
        r.finalizePeriod(P, root, 20, 0);
        vm.expectRevert();
        r.finalizePeriod(P, root, 41, 0);
        vm.expectRevert();
        r.finalizePeriod(P, root, 0, 61);
        vm.expectRevert();
        r.finalizePeriod(P, bytes32(0), 20, 0);
        r.finalizePeriod(P, root, 20, 0);
        vm.expectRevert();
        r.finalizePeriod(P, root, 20, 0);
        require(r.reserved() == 20 && r.available() == 80);
    }

    function testEmptyFinalizationReleasesOnce() public {
        open();
        vm.warp(1100);
        r.finalizePeriod(P, bytes32(0), 0, 0);
        require(r.reserved() == 0 && r.available() == 100);
        vm.expectRevert();
        r.finalizePeriod(P, bytes32(0), 0, 0);
    }

    function testRelayPaysOnlyRecipientAndReplayFails() public {
        settle(0, 20);
        vm.prank(B);
        r.claim(P, 0, A, 0, 20, proof());
        require(t.balanceOf(A) == 20 && t.balanceOf(B) == 0 && r.reserved() == 0 && r.available() == 80);
        vm.expectRevert();
        r.claim(P, 0, A, 0, 20, proof());
    }

    function testWrongRecipientAmountChannelIndexAndPeriod() public {
        settle(0, 20);
        vm.expectRevert();
        r.claim(P, 0, B, 0, 20, proof());
        vm.expectRevert();
        r.claim(P, 0, A, 0, 21, proof());
        vm.expectRevert();
        r.claim(P, 0, A, 1, 20, proof());
        vm.expectRevert();
        r.claim(P, 1, A, 0, 20, proof());
        vm.expectRevert();
        r.claim(keccak256("other"), 0, A, 0, 20, proof());
        require(!r.claimed(P, 0) && r.reserved() == 20);
    }

    function testChainDomainReplayFails() public {
        settle(0, 20);
        vm.chainId(4663);
        vm.expectRevert();
        r.claim(P, 0, A, 0, 20, proof());
        vm.chainId(46630);
        r.claim(P, 0, A, 0, 20, proof());
    }

    function testContractAndTokenDomainDiffer() public {
        SogdiaRewards other = new SogdiaRewards(t, address(this));
        TestToken otherToken = new TestToken(1);
        SogdiaRewards otherAsset = new SogdiaRewards(otherToken, address(this));
        require(r.leaf(P, 0, A, 0, 20) != other.leaf(P, 0, A, 0, 20));
        require(r.leaf(P, 0, A, 0, 20) != otherAsset.leaf(P, 0, A, 0, 20));
    }

    function testMaliciousRootCannotExceedDeclaredChannel() public {
        open();
        bytes32 root = r.leaf(P, 0, A, 0, 30);
        vm.warp(1100);
        r.finalizePeriod(P, root, 20, 0);
        vm.expectRevert();
        r.claim(P, 0, A, 0, 30, proof());
        require(!r.claimed(P, 0) && r.reserved() == 20);
    }

    function testOldUnclaimedBudgetCannotFundNewPeriod() public {
        settle(0, 20);
        vm.expectRevert();
        r.openPeriod(keccak256("new"), 1100, 1200, 81, 0, POLICY);
        r.openPeriod(keccak256("new"), 1100, 1200, 80, 0, POLICY);
        r.claim(P, 0, A, 0, 20, proof());
        require(r.reserved() == 80 && r.available() == 0);
    }

    function testTwoStepOwnershipAndRenunciationBlocked() public {
        r.transferOwnership(B);
        require(r.owner() == address(this));
        vm.prank(A);
        vm.expectRevert();
        r.acceptOwnership();
        vm.prank(B);
        r.acceptOwnership();
        require(r.owner() == B);
        vm.prank(B);
        vm.expectRevert();
        r.renounceOwnership();
    }

    function testTransferFailureAndTaxRollbackClaim() public {
        AdversarialToken bad = new AdversarialToken();
        SogdiaRewards d = new SogdiaRewards(bad, address(this));
        bad.approve(address(d), 100);
        d.fund(100);
        d.openPeriod(P, 1000, 1100, 40, 60, POLICY);
        bytes32 root = d.leaf(P, 0, A, 0, 20);
        vm.warp(1100);
        d.finalizePeriod(P, root, 20, 0);
        bad.configure(true, false, address(0), "");
        vm.expectRevert();
        d.claim(P, 0, A, 0, 20, proof());
        require(!d.claimed(P, 0) && d.reserved() == 20 && bad.balanceOf(A) == 0);
        bad.configure(false, true, address(0), "");
        vm.expectRevert();
        d.claim(P, 0, A, 0, 20, proof());
        require(!d.claimed(P, 0) && d.reserved() == 20 && bad.balanceOf(A) == 0);
        bad.configure(false, false, address(0), "");
        d.claim(P, 0, A, 0, 20, proof());
        require(bad.balanceOf(A) == 20);
    }

    function testTaxedFundingRejected() public {
        AdversarialToken bad = new AdversarialToken();
        SogdiaRewards d = new SogdiaRewards(bad, address(this));
        bad.approve(address(d), 100);
        bad.configure(false, true, address(0), "");
        vm.expectRevert();
        d.fund(100);
        require(bad.balanceOf(address(d)) == 0);
    }

    function testReentrantTokenCannotClaimTwice() public {
        AdversarialToken bad = new AdversarialToken();
        SogdiaRewards d = new SogdiaRewards(bad, address(this));
        bad.approve(address(d), 100);
        d.fund(100);
        d.openPeriod(P, 1000, 1100, 40, 60, POLICY);
        bytes32 root = d.leaf(P, 0, A, 0, 20);
        vm.warp(1100);
        d.finalizePeriod(P, root, 20, 0);
        bad.configure(false, false, address(d), abi.encodeCall(d.claim, (P, 0, A, 0, 20, proof())));
        d.claim(P, 0, A, 0, 20, proof());
        require(!bad.callbackSucceeded() && bad.balanceOf(A) == 20 && d.reserved() == 0);
    }

    function testFuzzConservation(uint96 fundingSeed, uint96 payoutSeed) public {
        uint256 funding = uint256(fundingSeed) + 1;
        uint256 payout = uint256(payoutSeed) % funding + 1;
        TestToken x = new TestToken(funding);
        SogdiaRewards d = new SogdiaRewards(x, address(this));
        x.approve(address(d), funding);
        d.fund(funding);
        d.openPeriod(P, 1000, 1100, funding, 0, POLICY);
        bytes32 root = d.leaf(P, 0, A, 0, payout);
        vm.warp(1100);
        d.finalizePeriod(P, root, payout, 0);
        require(d.reserved() + d.available() == funding);
        d.claim(P, 0, A, 0, payout, proof());
        require(x.balanceOf(A) == payout && d.available() == funding - payout && d.reserved() == 0);
    }
}
