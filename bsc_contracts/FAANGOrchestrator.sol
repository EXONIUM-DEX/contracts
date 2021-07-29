// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/Ownable.sol";
import "./libs/ReentrancyGuard.sol";
import "./FAANGToken.sol";

contract FAANGOrchestrator is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using Address for address;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up regardless of user's current rewardDept
        //
        // We do some fancy math here. Basically, any point in time, the amount of FAANG
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accFAANGPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accFAANGPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 lastRewardBlock; // Last block number that FAANGs distribution occurs.
        uint256 accFAANGPerShare; // Accumulated FAANG per share, times 1e12. See below.
        uint256 inActiveBlock;
    }

    // The FAANG Token!
    FAANGToken public FAANG;

    // FAANG tokens created per block.
    uint256 public FAANGPerBlock = 1 ether;

    // Block when mining starts
    uint256 startBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.

    // Pool Exists Mapper
    mapping(IBEP20 => bool) public poolExistence;
    // Pool ID Tracker Mapper
    mapping(IBEP20 => uint256) public poolIdForLpAddress;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event ClaimReward(address indexed user, uint256 pid, uint256 amount);

    constructor(
        FAANGToken _FAANG,
        uint256 _startBlock
    ) public {
        FAANG = _FAANG;
        startBlock = _startBlock;
    }

    // Get number of pools added.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function updateStartBlock(uint256 _newStartBlock) public onlyOwner {
        require(_newStartBlock > startBlock, "update startblock: new start block must be after previous start block");
        startBlock = _newStartBlock;
    }

    function getPoolIdForLpToken(IBEP20 _lpToken) external view returns (uint256) {
        require(poolExistence[_lpToken] != false, "getPoolIdForLpToken: do not exist");
        return poolIdForLpAddress[_lpToken];
    }

    // Modifier to check Duplicate pools
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        IBEP20 _lpToken,
        bool _withUpdate,
        uint256 _inactiveBlock
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(_inactiveBlock > startBlock, "Inactive block need to larger than startBlock");

        if (_withUpdate) {
            massUpdatePools();
        }

        poolExistence[_lpToken] = true;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                lastRewardBlock: block.number > startBlock ? block.number : startBlock,
                accFAANGPerShare: 0,
                inActiveBlock: _inactiveBlock
            })
        );

        poolIdForLpAddress[_lpToken] = poolInfo.length - 1;
    }

    function set(
        uint256 _pid,
        bool _withUpdate,
        uint256 _inactiveBlock
    ) public onlyOwner {
        require(_inactiveBlock > startBlock, "Inactive block need to larger than startBlock");

        if (_withUpdate) {
            massUpdatePools();
        }

        poolInfo[_pid].inActiveBlock = _inactiveBlock;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    function minCurrentBlockAndInactiveBlockIfExist(uint256 _pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        return block.number > pool.inActiveBlock ? pool.inActiveBlock : block.number;
    }

    // View function to see pending FAANGs on frontend.
    function pendingFAANG(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accFAANGPerShare = pool.accFAANGPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        uint256 blockToCalculateMultiplier = minCurrentBlockAndInactiveBlockIfExist(_pid);

        if (blockToCalculateMultiplier > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockToCalculateMultiplier);
            uint256 FAANGReward = multiplier.mul(FAANGPerBlock);

            accFAANGPerShare = accFAANGPerShare
                .add(
                    FAANGReward
                        .mul(1e12)
                        .div(lpSupply)
                );
        }

        uint256 pending = user.amount
            .mul(accFAANGPerShare)
            .div(1e12)
            .sub(user.rewardDebt);

        return pending.add(user.rewardLockedUp);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 blockToCalculateRewards = minCurrentBlockAndInactiveBlockIfExist(_pid);

        if (blockToCalculateRewards <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this)); // Get number of lp token this pool has. Example: total WETH this pool has accumulated.

        if (lpSupply == 0) {
            pool.lastRewardBlock = blockToCalculateRewards;

            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockToCalculateRewards); // For each block has passed, the reward will be multiplied.
        uint256 FAANGReward = multiplier.mul(FAANGPerBlock);

        FAANG.mint(address(this), FAANGReward); // Increase the number of FAANG this pool has.

        pool.accFAANGPerShare = pool.accFAANGPerShare
            .add(
                FAANGReward
                .mul(1e12)
                .div(lpSupply)
            );

        pool.lastRewardBlock = blockToCalculateRewards;
    }

    function canClaimFAANGRewards() public view returns (bool) {
        return block.number >= startBlock;
    }

    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];

        require(block.number <= pool.inActiveBlock, "deposit: staking period has ended");

        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        payOrLockupPendingFAANG(_pid);

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount
            .mul(pool.accFAANGPerShare)
            .div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        payOrLockupPendingFAANG(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount
            .mul(pool.accFAANGPerShare)
            .div(1e12);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Pay or lockup pending FAANG.
    function payOrLockupPendingFAANG(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pending = user.amount
            .mul(pool.accFAANGPerShare)
            .div(1e12)
            .sub(user.rewardDebt);

        if (canClaimFAANGRewards()) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                user.rewardLockedUp = 0;

                safeFAANGTransfer(msg.sender, totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);

        emit EmergencyWithdraw(msg.sender, _pid, user.amount);

        user.amount = 0;
        user.rewardDebt = 0;
    }

    // Safe FAANG transfer function, just in case if rounding error causes pool to not have enough FAANGs.
    function safeFAANGTransfer(address _to, uint256 _amount) internal {
        uint256 FAANGBal = FAANG.balanceOf(address(this));
        bool transferSuccess = false;

        if (_amount > FAANGBal) {
            transferSuccess = FAANG.transfer(_to, FAANGBal);
        } else {
            transferSuccess = FAANG.transfer(_to, _amount);
        }

        require(transferSuccess, "safeFAANGTransfer: transfer failed.");
    }
}
