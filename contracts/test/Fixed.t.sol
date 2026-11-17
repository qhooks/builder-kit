// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

// Regression tests for the patched QStakeModule and QRafflePot: the two reported attacks fail, and the
// accounting invariants hold. Run: forge test --match-path test/Fixed.t.sol

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "./Mocks.sol";
import {QStakeModule} from "../src/QStakeModule.sol";
import {QRafflePot} from "../src/QRafflePot.sol";

contract FixedStake is Test {
    MockERC20 token;
    MockERC20 quote;
    QStakeModule m;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address griefer = address(0xBAD);

    function setUp() public {
        vm.warp(1_800_000_000);
        token = new MockERC20("TKN");
        quote = new MockERC20("WETH");
        m = new QStakeModule(address(token), address(quote), address(0), 0);
        address[2] memory who = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            token.mint(who[i], 1_000_000e18);
            vm.prank(who[i]);
            token.approve(address(m), type(uint256).max);
        }
        quote.mint(griefer, 1e18);
    }

    function _now() internal view returns (uint256) {
        return vm.getBlockTimestamp(); // via_ir can re-read block.timestamp after vm.warp
    }

    function _stake(address who, uint256 a) internal {
        vm.prank(who);
        m.stake(a);
    }

    function _pay(uint256 a) internal {
        quote.mint(address(m), a);
        m.sync();
    }

    // The reported attack: hourly 1-wei donations + sync. Fixed: the honest staker's 24 h earnings are unchanged.
    function test_dustSyncsNoLongerSlowTheStream() public {
        _stake(alice, 1000e18);
        // Align to the grid so the payout's window is exactly DURATION + up to one EPOCH; compare against a twin.
        QStakeModule twin = new QStakeModule(address(token), address(quote), address(0), 0);
        vm.prank(alice);
        token.approve(address(twin), type(uint256).max);
        vm.prank(alice);
        twin.stake(1000e18);
        quote.mint(address(m), 900e18);
        quote.mint(address(twin), 900e18);
        m.sync();
        twin.sync();
        uint256 t0 = _now();
        for (uint256 h = 1; h <= 48; ++h) {
            vm.warp(t0 + h * 1 hours);
            vm.prank(griefer);
            quote.transfer(address(m), 1);
            m.sync();
            if (h == 24) {
                (, uint256 a) = m.earned(alice);
                (, uint256 b) = twin.earned(alice);
                console2.log("24h earned, griefed module:", a);
                console2.log("24h earned, untouched twin:", b);
                assertGe(a, b, "dust syncs must not slow the payout");
                assertLe(a - b, 24, "only the dust itself is extra");
                assertGt(b, 900e18 * 24 / 30 - 1e18, "streams over DURATION..DURATION+EPOCH");
            }
        }
        (, uint256 fin) = m.earned(alice);
        assertApproxEqAbs(fin, 900e18, 1e6, "everything paid within 30 h, dust aside");
    }

    // A sync with no new income changes nothing but the accrual clock.
    function test_noIncomeSyncIsNoop() public {
        _stake(alice, 1000e18);
        _pay(500e18);
        vm.warp(_now() + 3 hours);
        (uint256 r0, uint64 f0, uint256 b0, uint256 i0) = m.stream(1);
        (, uint256 e0) = m.earned(alice);
        m.sync();
        m.sync();
        (uint256 r1, uint64 f1, uint256 b1, uint256 i1) = m.stream(1);
        (, uint256 e1) = m.earned(alice);
        assertEq(r0, r1);
        assertEq(f0, f1);
        assertEq(b0, b1);
        assertEq(i0, i1);
        assertEq(e0, e1);
    }

    // New income never moves the end of income already streaming.
    function test_laterIncomeDoesNotDelayEarlierIncome() public {
        _stake(alice, 1000e18);
        _pay(600e18);
        (, uint64 f0,,) = m.stream(1);
        vm.warp(_now() + 10 hours); // a later epoch: its own tranche
        _pay(1); // dust
        _pay(300e18);
        vm.warp(f0);
        // All of the first payout has streamed by its original end.
        (, uint256 e) = m.earned(alice);
        assertGe(e, 600e18 - 1e6);
    }

    // Anti-JIT kept: income streams over at least DURATION, so one block around a payout earns ~nothing.
    function test_justInTimeStakerEarnsAlmostNothing() public {
        _stake(alice, 1000e18);
        vm.warp((_now() / m.EPOCH() + 1) * m.EPOCH() - 1 minutes); // one minute before the next epoch boundary
        _stake(bob, 1000e18);
        _pay(1000e18);
        (, uint64 finish,,) = m.stream(1);
        assertEq(uint256(finish) - _now(), 1 days + 1 minutes, "exercise the shortest stream window");
        vm.warp(_now() + 12);
        vm.prank(bob);
        m.exit();
        uint256 got = quote.balanceOf(bob);
        assertLe(got, uint256(1000e18) * 12 / 1 days, "<= 12 s of a 1-day stream for half the stake");
    }

    // Conservation across random flows: nothing is created, the module stays solvent, all income ends up claimable.
    function testFuzz_conservation(uint96[6] memory pays, uint32[6] memory gaps, uint96[6] memory stakes, bool[6] memory flips)
        public
    {
        uint256 paid;
        for (uint256 i; i < 6; ++i) {
            address who = flips[i] ? alice : bob;
            uint256 s = bound(stakes[i], 1, 100_000e18);
            if (m.staked(who) >= s && flips[(i + 1) % 6]) {
                vm.prank(who);
                m.unstake(s);
            } else {
                _stake(who, s);
            }
            uint256 p = bound(pays[i], 0, 1_000_000e18);
            paid += p;
            _pay(p);
            vm.warp(_now() + bound(gaps[i], 0, 2 days));
            assertGe(quote.balanceOf(address(m)), _bookedQuote(), "solvent");
        }
        if (m.totalStaked() == 0) _stake(alice, 1e18);
        vm.warp(_now() + 31 hours);
        m.sync(); // idle re-streams for current stakers
        vm.warp(_now() + 31 hours);
        vm.prank(alice);
        m.claim();
        vm.prank(bob);
        m.claim();
        uint256 out = quote.balanceOf(alice) + quote.balanceOf(bob);
        assertLe(out, paid, "never pays more than came in");
        assertApproxEqAbs(out, paid, 1e9, "everything but rounding dust paid out");
        assertGe(quote.balanceOf(address(m)), _bookedQuote());
    }

    function _bookedQuote() internal view returns (uint256 b) {
        (,, b,) = m.stream(1);
    }
}

contract FixedRaffle is Test {
    MockERC20 token;
    MockERC20 quote;
    QRafflePot pot;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address keeper = address(0xC0FFEE);

    function setUp() public {
        vm.warp(1_800_000_000);
        vm.roll(1_000_000);
        token = new MockERC20("TKN");
        quote = new MockERC20("WETH");
        pot = new QRafflePot(address(token), address(quote), address(0), 0);
        address[2] memory who = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            token.mint(who[i], 1000e18);
            vm.startPrank(who[i]);
            token.approve(address(pot), type(uint256).max);
            pot.enter(100e18);
            vm.stopPrank();
        }
        quote.mint(address(pot), 10e18);
        pot.sync(); // count the pot
        vm.warp(vm.getBlockTimestamp() + 1 days + 1);
    }

    function _winnerFor(uint256 r, bytes32 h) internal view returns (address) {
        (uint256 w,,,,,) = pot.rounds(r);
        uint256 x = uint256(keccak256(abi.encode(h, r, address(pot)))) % w;
        return x < w / 2 ? alice : bob;
    }

    function _findHash(uint256 r, address want, uint256 salt) internal view returns (bytes32 h) {
        for (uint256 i;; ++i) {
            h = keccak256(abi.encode("h", salt, i));
            if (_winnerFor(r, h) == want) return h;
        }
    }

    function _solvent() internal view {
        (uint256 t, uint256 q) = (token.balanceOf(address(pot)), quote.balanceOf(address(pot)));
        (uint256 wa0, uint256 wa1) = pot.won(alice);
        (uint256 wb0, uint256 wb1) = pot.won(bob);
        (uint256 wk0, uint256 wk1) = pot.won(keeper);
        assertGe(t, pot.totalDeposits() + pot.pot(0) + wa0 + wb0 + wk0);
        assertGe(q, pot.pot(1) + wa1 + wb1 + wk1);
    }

    // The reported attack: Bob saw a losing hash, let it expire, re-armed. Fixed: the round closes, no re-roll.
    function test_expiredRoundCannotBeReArmed() public {
        vm.prank(bob);
        assertFalse(pot.draw()); // arm
        (, uint64 db,,,,) = pot.rounds(0);
        bytes32 h1 = _findHash(0, alice, 1);
        vm.roll(db + 1);
        vm.setBlockhash(db, h1);
        // Bob stalls until the hash is gone.
        vm.roll(db + 257);
        vm.prank(bob);
        assertFalse(pot.draw());
        (, uint64 db2, bool drawn, address w,,) = pot.rounds(0);
        assertEq(db2, db, "not re-armed");
        assertTrue(drawn);
        assertEq(w, address(0), "no winner");
        assertEq(pot.drawIndex(), 1);
        assertEq(pot.pot(1), 10e18, "pot carries over untouched");
        vm.expectRevert(bytes("QRaffle: nothing to draw"));
        vm.prank(bob);
        pot.draw();
        vm.expectRevert(bytes("QRaffle: nothing won"));
        vm.prank(bob);
        pot.claim();
        // Deposits come back as usual.
        vm.prank(alice);
        pot.withdraw(0);
        vm.prank(bob);
        pot.withdraw(0);
        assertEq(token.balanceOf(alice), 1000e18);
        assertEq(token.balanceOf(bob), 1000e18);
        _solvent();
    }

    // A timely draw pays the winner 99% and the drawer 1%, and nothing else changes.
    function test_timelyDrawPaysWinnerAndBounty() public {
        vm.prank(keeper);
        pot.draw();
        (, uint64 db,,,,) = pot.rounds(0);
        bytes32 h = _findHash(0, bob, 7);
        vm.roll(db + 1);
        vm.setBlockhash(db, h);
        (, uint256 nq) = pot.nextPrize();
        assertEq(nq, 9.9e18);
        vm.prank(keeper);
        assertTrue(pot.draw());
        (,,, address w, uint256 pt, uint256 pq) = pot.rounds(0);
        assertEq(w, bob);
        assertEq(pt, 0);
        assertEq(pq, 9.9e18);
        _solvent();
        vm.prank(bob);
        (, uint256 q) = pot.claim();
        vm.prank(keeper);
        (, uint256 k) = pot.claim();
        assertEq(q, 9.9e18);
        assertEq(k, 0.1e18);
        assertEq(quote.balanceOf(address(pot)), 0);
    }

    // The carried-over pot goes to the next entered round's winner; the expired round's entrants get no second roll
    // inside the old round, only a normal entry in a new one alongside everyone else.
    function test_carriedPotPaysNextRound() public {
        vm.prank(bob);
        pot.draw();
        (, uint64 db,,,,) = pot.rounds(0);
        vm.roll(db + 300);
        pot.draw(); // expires round 0
        uint256 r1 = pot.currentRound();
        vm.prank(alice);
        pot.withdraw(0);
        vm.prank(alice);
        pot.enter(100e18); // round r1
        quote.mint(address(pot), 2e18); // new income
        vm.warp(vm.getBlockTimestamp() + 1 days);
        pot.draw(); // arm r1
        (, uint64 db1,,,,) = pot.rounds(r1);
        vm.roll(db1 + 1);
        vm.setBlockhash(db1, keccak256("any"));
        vm.prank(keeper);
        assertTrue(pot.draw());
        (,,, address w,, uint256 pq) = pot.rounds(r1);
        assertEq(w, alice, "sole entrant");
        assertEq(pq, 12e18 - 12e18 / 100);
        _solvent();
    }

    // Arming twice before the draw block is impossible to exploit: the second call just waits.
    function test_cannotReArmBeforeDrawBlock() public {
        pot.draw();
        (, uint64 db,,,,) = pot.rounds(0);
        vm.expectRevert(bytes("QRaffle: too early"));
        pot.draw();
        (, uint64 db2,,,,) = pot.rounds(0);
        assertEq(db, db2);
    }
}
