// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./openzeppelin/contracts/utils/Address.sol";
import "./openzeppelin/contracts/utils/math/SafeMath.sol";
import "./openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IController.sol";
import "./interface/IVault.sol";
import "./FeeRewardForwarder.sol";
import "./inheritance/Governable.sol";

contract Controller is IController, Governable{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // external parties
    address public override feeRewardForwarder;

    mapping (address => bool) public override greyList;

    // All vaults that we have
    mapping (address => bool) public vaults;

    uint256 public constant override profitSharingNumerator = 5;
    uint256 public constant override profitSharingDenominator = 100;

    event SharePriceChangeLog(
      address indexed vault,
      address indexed strategy,
      uint256 oldSharePrice,
      uint256 newSharePrice,
      uint256 timestamp
    );

    modifier validVault(address _vault){
        require(vaults[_vault], "vault does not exist");
        _;
    }

    mapping (address => bool) public hardWorkers;

    modifier onlyHardWorkerOrGovernance() {
        require(hardWorkers[msg.sender] || (msg.sender == governance()),
        "only hard worker can call this");
        _;
    }

    constructor(address _storage, address _feeRewardForwarder)

    Governable(_storage) public {
        require(_feeRewardForwarder != address(0), "feeRewardForwarder should not be empty");
        feeRewardForwarder = _feeRewardForwarder;
    }

    function addHardWorker(address _worker) public onlyGovernance {
      require(_worker != address(0), "_worker must be defined");
      hardWorkers[_worker] = true;
    }

    function removeHardWorker(address _worker) public onlyGovernance {
      require(_worker != address(0), "_worker must be defined");
      hardWorkers[_worker] = false;
    }

    function hasVault(address _vault) external override returns (bool) {
      return vaults[_vault];
    }

    // Only smart contracts will be affected by the greyList.
    function addToGreyList(address _target) public onlyGovernance {
        greyList[_target] = true;
    }

    function removeFromGreyList(address _target) public onlyGovernance {
        greyList[_target] = false;
    }

    function setFeeRewardForwarder(address _feeRewardForwarder) public override onlyGovernance {
      require(_feeRewardForwarder != address(0), "new reward forwarder should not be empty");
      feeRewardForwarder = _feeRewardForwarder;
    }

    function addVaultAndStrategy(address _vault, address _strategy) external override onlyGovernance {
        require(_vault != address(0), "new vault shouldn't be empty");
        require(!vaults[_vault], "vault already exists");
        require(_strategy != address(0), "new strategy shouldn't be empty");

        vaults[_vault] = true;
        // adding happens while setting
        IVault(_vault).setStrategy(_strategy);
    }

    function doHardWork(address _vault) external override onlyHardWorkerOrGovernance validVault(_vault) {
        uint256 oldSharePrice = IVault(_vault).getPricePerFullShare();
        IVault(_vault).doHardWork();
        emit SharePriceChangeLog(
          _vault,
          IVault(_vault).strategy(),
          oldSharePrice,
          IVault(_vault).getPricePerFullShare(),
          block.timestamp
        );
    }

    // transfers token in the controller contract to the governance
    function salvage(address _token, uint256 _amount) external override onlyGovernance {
        IERC20(_token).safeTransfer(governance(), _amount);
    }

    function notifyFee(address underlying, uint256 fee) external override {
      if (fee > 0) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), fee);
        IERC20(underlying).safeApprove(feeRewardForwarder, 0);
        IERC20(underlying).safeApprove(feeRewardForwarder, fee);
        FeeRewardForwarder(feeRewardForwarder).poolNotifyFixedTarget(underlying, fee);
      }
    }
}
