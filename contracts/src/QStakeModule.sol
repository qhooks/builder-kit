// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {QModuleBase} from "./QModuleBase.sol";

/// @title QStakeModule
/// @notice Holder staking as a marketplace module: QStakeVault's logic on QModuleBase. Stake the launch token, earn
/// what the launch pays this module (less its builder's share, if any) in the token and its pair currency, streamed
/// over at least DURATION so staking for one block around a payout earns almost nothing. Funds that stream while
/// nobody is staked are kept and streamed again once someone is. Staked tokens are never counted as income. No lockup,
/// no owner. The same function names and selectors as QStakeVault, so one Staking panel drives both.
///
/// Streams: income is added to a tranche whose end is fixed on a clock grid (the end of the current EPOCH plus
/// DURATION, so every payout streams for between DURATION and DURATION + EPOCH). A later arrival in the same epoch only
/// raises that tranche's rate; it never moves the end of income that is already streaming, so a sync, or a dust
/// donation followed by a sync, cannot slow anyone's payout. A sync with no new income only moves the stream to now.
contract QStakeModule is QModuleBase {
    uint256 public constant DURATION = 1 days;
    /// @notice Width of the clock grid tranche ends sit on.
    uint256 public constant EPOCH = 6 hours;
    uint256 private constant SLOTS = DURATION / EPOCH + 1; // tranches that can be live at once
    uint256 private constant E18 = 1e18;
    uint256 private constant E36 = 1e36;

    struct Tranche {
        uint256 rate; // reward per second, scaled by 1e18
        uint64 finish;
    }

    struct Stream {
        Tranche[SLOTS] tranches;
        uint64 last;
        uint256 acc; // reward per staked unit, scaled by 1e36
        uint256 booked; // the module's share of income received so far and not yet paid out
        uint256 idle; // streamed while nobody was staked; streamed again on the next sync
    }

    uint256 public totalStaked;
    mapping(address => uint256) public staked;
    Stream[2] internal _streams;
    mapping(address => uint256[2]) internal _debt;
    mapping(address => uint256[2]) internal _owed;

    event Staked(address indexed who, uint256 amount);
    event Unstaked(address indexed who, uint256 amount);
    event Claimed(address indexed who, uint256 tokenAmount, uint256 quoteAmount);
    event Streamed(address indexed currency, uint256 amount, uint256 rate, uint64 finish);

    constructor(address token_, address quote_, address builder_, uint16 builderBps_)
        QModuleBase(token_, quote_, builder_, builderBps_)
    {}

    function kind() external pure override returns (string memory) {
        return "stake";
    }

    /// @notice Stakes `amount` of the token (the amount that actually arrives counts).
    function stake(uint256 amount) external guarded {
        require(amount != 0, "QStake: amount");
        _update(msg.sender);
        uint256 got = _pull(token, msg.sender, amount);
        require(got != 0, "QStake: amount");
        staked[msg.sender] += got;
        totalStaked += got;
        emit Staked(msg.sender, got);
    }

    /// @notice Unstakes `amount`; rewards earned so far stay claimable.
    function unstake(uint256 amount) public guarded {
        _update(msg.sender);
        require(amount != 0 && amount <= staked[msg.sender], "QStake: amount");
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        _send(token, msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /// @notice Pays out everything earned so far, in the token and the quote.
    function claim() public guarded returns (uint256 tokenAmount, uint256 quoteAmount) {
        _update(msg.sender);
        tokenAmount = _payOut(0, msg.sender);
        quoteAmount = _payOut(1, msg.sender);
        emit Claimed(msg.sender, tokenAmount, quoteAmount);
    }

    /// @notice Unstakes everything and claims.
    function exit() external {
        uint256 s = staked[msg.sender];
        if (s != 0) unstake(s);
        claim();
    }

    /// @notice Starts streaming anything that has arrived since the last interaction. Anyone can call it.
    function sync() external guarded {
        _syncAll();
    }

    /// @notice What `who` could claim now (from streams already started; call `sync` to start new arrivals).
    function earned(address who) external view returns (uint256 tokenAmount, uint256 quoteAmount) {
        return (_earnedView(who, 0), _earnedView(who, 1));
    }

    /// @notice A currency's stream: reward per second now (1e18-scaled, all live tranches), when the last tranche
    /// ends, and what it still holds.
    function stream(uint256 i) external view returns (uint256 rate, uint64 finish, uint256 booked, uint256 idle) {
        Stream storage s = _streams[i];
        for (uint256 k; k < SLOTS; ++k) {
            Tranche storage t = s.tranches[k];
            if (t.finish > block.timestamp) {
                rate += t.rate;
                if (t.finish > finish) finish = t.finish;
            }
        }
        return (rate, finish, s.booked, s.idle);
    }

    function _reserved(uint256 i) internal view override returns (uint256) {
        return (i == 0 ? totalStaked : 0) + _streams[i].booked;
    }

    function _syncAll() internal override {
        _sync(0);
        _sync(1);
    }

    function _update(address who) private {
        for (uint256 i; i < 2; ++i) {
            _sync(i);
            uint256 acc = _streams[i].acc;
            _owed[who][i] += staked[who] * (acc - _debt[who][i]) / E36;
            _debt[who][i] = acc;
        }
    }

    /// Moves the stream to now, counts new income (the builder's cut comes off first), then streams it plus
    /// anything that streamed while nobody was staked. With no new income and nothing idle this only accrues.
    function _sync(uint256 i) private {
        Stream storage s = _streams[i];
        _accrue(s);
        _intake(i); // books and streams new income through _income
        uint256 idle = s.idle;
        if (idle != 0) {
            s.idle = 0;
            _add(i, idle);
        }
    }

    function _income(uint256 i, uint256 net) internal override {
        _streams[i].booked += net;
        _add(i, net);
    }

    /// Adds `amount` to the tranche ending at the grid end for now. Other tranches, and what this tranche already
    /// streams, keep their rate and end. Runs after `_accrue`, so a finished tranche has been fully counted.
    function _add(uint256 i, uint256 amount) private {
        if (amount == 0) return;
        Stream storage s = _streams[i];
        uint256 end = (block.timestamp / EPOCH + 1) * EPOCH + DURATION;
        (Tranche storage t, bool live) = _tranche(s, end);
        if (!live) {
            t.rate = 0;
            t.finish = uint64(end);
        }
        uint256 r = amount * E18 / (end - block.timestamp);
        t.rate += r;
        emit Streamed(currency(i), amount, r, uint64(end));
    }

    /// The tranche that ends at `end` (live = true), else a finished one to reuse. Only tranches opened in the last
    /// SLOTS - 1 epochs can still be running and each epoch opens at most one, so a finished slot always exists.
    function _tranche(Stream storage s, uint256 end) private view returns (Tranche storage t, bool live) {
        uint256 freeK = SLOTS;
        for (uint256 k; k < SLOTS; ++k) {
            uint256 f = s.tranches[k].finish;
            if (f == end) return (s.tranches[k], true);
            if (freeK == SLOTS && f <= block.timestamp) freeK = k;
        }
        require(freeK < SLOTS, "QStake: tranches"); // unreachable
        return (s.tranches[freeK], false);
    }

    /// Credits everything every tranche streamed since `last`. Each tranche runs at a constant rate until its own end.
    function _accrue(Stream storage s) private {
        uint256 last = s.last;
        if (block.timestamp <= last) return;
        uint256 amount = _streamed(s, last);
        s.last = uint64(block.timestamp);
        if (amount == 0) return;
        if (totalStaked != 0) s.acc += amount * E18 / totalStaked;
        else s.idle += amount / E18;
    }

    /// What the tranches streamed between `from` and now (1e18-scaled).
    function _streamed(Stream storage s, uint256 from) private view returns (uint256 amount) {
        for (uint256 k; k < SLOTS; ++k) {
            Tranche storage t = s.tranches[k];
            uint256 f = t.finish;
            if (f <= from) continue;
            amount += t.rate * ((block.timestamp < f ? block.timestamp : f) - from);
        }
    }

    function _earnedView(address who, uint256 i) private view returns (uint256) {
        Stream storage s = _streams[i];
        uint256 acc = s.acc;
        if (block.timestamp > s.last && totalStaked != 0) acc += _streamed(s, s.last) * E18 / totalStaked;
        return _owed[who][i] + staked[who] * (acc - _debt[who][i]) / E36;
    }

    function _payOut(uint256 i, address to) private returns (uint256 amount) {
        amount = _owed[to][i];
        if (amount == 0) return 0;
        _owed[to][i] = 0;
        _streams[i].booked -= amount;
        _send(currency(i), to, amount);
    }
}
