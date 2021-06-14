// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/Ownable.sol";
import "./TEXOToken.sol";
import "./libs/ReentrancyGuard.sol";

contract TEXOOrchestrator is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Address for address;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLockedUp; // Reward locked up regardless of user's current rewardDept
        //
        // We do some fancy math here. Basically, any point in time, the amount of tEXOs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTEXOPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTEXOPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. tEXOs to distribute per block.
        uint256 blockToReceiveReward; // Block number at which to allow receiving reward
        uint256 inActiveBlock; // Block at which to stop staking and generating rewards
        uint256 lastRewardBlock; // Last block number that TEXOs distribution occurs.
        uint256 accTEXOPerShare; // Accumulated tEXOs per share, times 1e12. See below.
        uint16 depositFeeBP; // Deposit fee in basis points
    }

    // The tEXO Token!
    TEXOToken public tEXO;
    // Dev address.
    address public devAddr;
    // tEXO tokens created per block.
    uint256 public tEXOPerBlock;
    // Deposit Fee address
    address public feeAddress;

    // Block height at which to reduce emission rate
    uint256 public blockToStartReducingEmissionRate;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Referral Bonus in basis points. Initially set to 2%
    uint256 public refBonusBP = 200;
    // Max deposit fee: 4%.
    uint16 public constant MAXIMUM_DEPOSIT_FEE_BP = 400;
    // Max referral commission rate: 20%.
    uint16 public constant MAXIMUM_REFERRAL_BP = 2000;
    // Referral Mapping
    mapping(address => address) public referrers; // account_address -> referrer_address
    mapping(address => uint256) public referredCount; // referrer_address -> num_of_referred
    // Pool Exists Mapper
    mapping(IBEP20 => bool) public poolExistence;
    // Pool ID Tracker Mapper
    mapping(IBEP20 => uint256) public poolIdForLpAddress;

    // Initial emission rate: 0.5 tEXO per block.
    uint256 public constant INITIAL_EMISSION_RATE = 500 finney;

    // Minimum emission rate: 0.1 tEXO per block.
    uint256 public constant MINIMUM_EMISSION_RATE = 100 finney;

    // Reduce emission every 28,800 blocks ~ 24 hours.
    uint256 public constant EMISSION_REDUCTION_PERIOD_BLOCKS = 28800;
    // Emission reduction rate per period in basis points: 15%.
    uint256 public constant EMISSION_REDUCTION_RATE_PER_PERIOD = 1500;
    // Last reduction period index
    uint256 public lastReductionPeriodIndex = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event ClaimReward(address indexed user, uint256 pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed _devAddress);
    event SetDevAddress(address indexed user, address indexed _feeAddress);
    event Referral(address indexed _referrer, address indexed _user);
    event ReferralPaid(address indexed _user, address indexed _userTo, uint256 _reward);
    event ReferralBonusBpChanged(uint256 _oldBp, uint256 _newBp);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event BlockToStartEmissionRateUpdated(address indexed caller, uint256 previousValue, uint256 newValue);

    constructor(
        TEXOToken _tEXO,
        address _devAddr,
        address _feeAddress,
        uint256 _blockToStartReducingEmissionRate
    ) public {
        tEXO = _tEXO;
        devAddr = _devAddr;
        feeAddress = _feeAddress;
        tEXOPerBlock = INITIAL_EMISSION_RATE;
        blockToStartReducingEmissionRate = _blockToStartReducingEmissionRate;
    }

    // Get number of pools added.
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
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
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint16 _depositFeeBP,
        bool _withUpdate,
        uint256 _blockToReceiveReward,
        uint256 _startGenerateRewardBlock,
        uint256 _inActiveBlock
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEE_BP, "add: invalid deposit fee basis points");
        require(_blockToReceiveReward > 0, "add: block to receive reward is required ");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;

        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: _startGenerateRewardBlock > 0 ? _startGenerateRewardBlock : block.number,
                accTEXOPerShare: 0,
                depositFeeBP: _depositFeeBP,
                blockToReceiveReward: _blockToReceiveReward,
                inActiveBlock: _inActiveBlock > 0 ? _inActiveBlock : 0
            })
        );

        poolIdForLpAddress[_lpToken] = poolInfo.length - 1;
    }

    // Update the given pool's tEXO allocation point and deposit fee. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _depositFeeBP,
        bool _withUpdate,
        uint256 _blockToReceiveReward,
        uint256 _inActiveBlock
    ) public onlyOwner {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEE_BP, "set: invalid deposit fee basis points");
        require(_blockToReceiveReward > 0, "set: block to receive reward is required");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );

        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].blockToReceiveReward = _blockToReceiveReward;
        poolInfo[_pid].inActiveBlock = _inActiveBlock > 0 ? _inActiveBlock : 0;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending tEXOs on frontend.
    function pendingTEXO(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 accTEXOPerShare = pool.accTEXOPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));

        uint256 blockToCalculateMultiplier = minCurrentBlockAndInactiveBlockIfExist(_pid);

        if (blockToCalculateMultiplier > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockToCalculateMultiplier);
            uint256 tEXOReward = multiplier
                .mul(tEXOPerBlock)
                .mul(pool.allocPoint)
                .div(totalAllocPoint);

            accTEXOPerShare = accTEXOPerShare
                .add(
                    tEXOReward
                        .mul(1e12)
                        .div(lpSupply)
                );
        }

        uint256 pending = user.amount
            .mul(accTEXOPerShare)
            .div(1e12)
            .sub(user.rewardDebt);

        return pending.add(user.rewardLockedUp);
    }

    function minCurrentBlockAndInactiveBlockIfExist(uint256 _pid) internal view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.inActiveBlock == 0) {
            return block.number;
        }

        return block.number > pool.inActiveBlock ? pool.inActiveBlock : block.number;
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

        uint256 blockToCalculateMultiplier = minCurrentBlockAndInactiveBlockIfExist(_pid);

        if (blockToCalculateMultiplier <= pool.lastRewardBlock) {
            return;
        }

        uint256 lpSupply = pool.lpToken.balanceOf(address(this)); // Get number of lp token this pool has. Example: total WETH this pool has accumulated.

        if (lpSupply == 0 || pool.allocPoint == 0) { // If pool initially has no staked WETH token, or pool has no allocation points.
            pool.lastRewardBlock = blockToCalculateMultiplier;

            return;
        }

        uint256 multiplier = getMultiplier(pool.lastRewardBlock, blockToCalculateMultiplier); // For each block has passed, the reward will be multiplied.
        uint256 tEXOReward = multiplier
            .mul(tEXOPerBlock)
            .mul(pool.allocPoint)
            .div(totalAllocPoint);

        tEXO.mint(devAddr, tEXOReward.div(10)); // Reward dev 10% of the tEXO reward created for each block.
        tEXO.mint(address(this), tEXOReward); // Increase the number of tEXO this pool has.

        pool.accTEXOPerShare = pool.accTEXOPerShare
            .add(
                tEXOReward
                .mul(1e12)
                .div(lpSupply)
            );

        pool.lastRewardBlock = blockToCalculateMultiplier;
    }

    function canClaimReward(uint256 _pid) public view returns (bool) {
        PoolInfo storage pool = poolInfo[_pid];

        return pool.blockToReceiveReward <= block.number;
    }

    // Deposit LP tokens to MasterChef for tEXO allocation with referral.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) public nonReentrant {
        require(_referrer == address(_referrer),"deposit: Invalid referrer address");

        PoolInfo storage pool = poolInfo[_pid];
        if (pool.inActiveBlock > 0) {
            require(block.number <= pool.inActiveBlock, "deposit: staking period has ended");
        }

        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        payOrLockupPendingTEXO(_pid);

        if (_amount > 0 && _referrer != address(0) && _referrer != msg.sender) {
            setReferral(msg.sender, _referrer);
        }

        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount
                    .mul(pool.depositFeeBP)
                    .div(10000);

                user.amount = user.amount
                    .add(_amount)
                    .sub(depositFee);

                pool.lpToken.safeTransfer(feeAddress, depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }

        user.rewardDebt = user.amount
            .mul(pool.accTEXOPerShare)
            .div(1e12);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);

        payOrLockupPendingTEXO(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.rewardDebt = user.amount
            .mul(pool.accTEXOPerShare)
            .div(1e12);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Pay or lockup pending tEXO.
    function payOrLockupPendingTEXO(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 pending = user.amount
            .mul(pool.accTEXOPerShare)
            .div(1e12)
            .sub(user.rewardDebt);

        if (canClaimReward(_pid)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                user.rewardLockedUp = 0;

                // send rewards
                safeTEXOTransfer(msg.sender, totalRewards);
                payReferralCommission(msg.sender, totalRewards);
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

    // Safe tEXO transfer function, just in case if rounding error causes pool to not have enough tEXOs.
    function safeTEXOTransfer(address _to, uint256 _amount) internal {
        uint256 tEXOBal = tEXO.balanceOf(address(this));
        bool transferSuccess = false;

        if (_amount > tEXOBal) {
            transferSuccess = tEXO.transfer(_to, tEXOBal);
        } else {
            transferSuccess = tEXO.transfer(_to, _amount);
        }

        require(transferSuccess, "safeTEXOTransfer: transfer failed.");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) public {
        require(_devaddr != address(0), "dev: invalid address");
        require(msg.sender == devAddr, "dev: wut?");

        devAddr = _devaddr;

        emit SetDevAddress(msg.sender, _devaddr);
    }

    // Update fee address by the previous fee address.
    function setFeeAddress(address _feeAddress) public {
        require(_feeAddress != address(0), "setFeeAddress: invalid address");
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");

        feeAddress = _feeAddress;

        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    // Reduce emission rate by 15% every 28,800 blocks ~ 24hours till the emission rate is 0.05 tEXO. This function can be called publicly.
    function reduceEmissionRateWithDefaultRate() public {
        require(block.number > blockToStartReducingEmissionRate, "reduceEmissionRateWithDefaultRate: Can only be called after specified block starts");
        require(tEXOPerBlock > MINIMUM_EMISSION_RATE, "reduceEmissionRateWithDefaultRate: Emission rate has reached the minimum threshold");

        uint256 currentIndex = block.number.sub(blockToStartReducingEmissionRate).div(EMISSION_REDUCTION_PERIOD_BLOCKS);
        if (currentIndex <= lastReductionPeriodIndex) {
            return;
        }

        uint256 newEmissionRate = tEXOPerBlock;
        for (uint256 index = lastReductionPeriodIndex; index < currentIndex; ++index) {
            newEmissionRate = newEmissionRate
                .mul(1e4 - EMISSION_REDUCTION_RATE_PER_PERIOD)
                .div(1e4);
        }

        newEmissionRate = newEmissionRate < MINIMUM_EMISSION_RATE ? MINIMUM_EMISSION_RATE : newEmissionRate;
        if (newEmissionRate >= tEXOPerBlock) {
            return;
        }

        massUpdatePools();

        lastReductionPeriodIndex = currentIndex;
        uint256 previousEmissionRate = tEXOPerBlock;
        tEXOPerBlock = newEmissionRate;

        emit EmissionRateUpdated(msg.sender, previousEmissionRate, newEmissionRate);
    }

    function setEmissionRate(uint256 newEmissionRate) public onlyOwner {
        uint256 previousEmissionRate = tEXOPerBlock;
        tEXOPerBlock = newEmissionRate;

        massUpdatePools();

        emit EmissionRateUpdated(msg.sender, previousEmissionRate, newEmissionRate);
    }

    function setBlockToStartReducingEmissionRate(uint256 newBlockToStartReducingEmissionRate) public onlyOwner {
        uint256 previousBlockToStartReducingEmissionRate = blockToStartReducingEmissionRate;
        blockToStartReducingEmissionRate = newBlockToStartReducingEmissionRate;

        emit BlockToStartEmissionRateUpdated(msg.sender, previousBlockToStartReducingEmissionRate, newBlockToStartReducingEmissionRate);
    }

    // Set Referral Address for a user
    function setReferral(address _user, address _referrer) internal {
        if (_referrer == address(_referrer) && referrers[_user] == address(0) && _referrer != address(0) && _referrer != _user) {
            referrers[_user] = _referrer;
            referredCount[_referrer] += 1;
            emit Referral(_user, _referrer);
        }
    }

    // Get Referral Address for a Account
    function getReferral(address _user) public view returns (address) {
        return referrers[_user];
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        address referrer = getReferral(_user);
        if (referrer != address(0) && referrer != _user && refBonusBP > 0) {
            uint256 refBonusEarned = _pending.mul(refBonusBP).div(10000);
            tEXO.mint(referrer, refBonusEarned);
            emit ReferralPaid(_user, referrer, refBonusEarned);
        }
    }

    // Referral Bonus in basis points.
    // Initially set to 2%, this this the ability to increase or decrease the Bonus percentage based on
    // community voting and feedback.
    function updateReferralBonusBp(uint256 _newRefBonusBp) public onlyOwner {
        require(_newRefBonusBp <= MAXIMUM_REFERRAL_BP, "updateRefBonusPercent: invalid referral bonus basis points");
        require(_newRefBonusBp != refBonusBP, "updateRefBonusPercent: same bonus bp set");
        uint256 previousRefBonusBP = refBonusBP;
        refBonusBP = _newRefBonusBp;
        emit ReferralBonusBpChanged(previousRefBonusBP, _newRefBonusBp);
    }
}
