//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../masterchef/NativeBaseStrategy.sol";

contract NativeStrategy_TEXO_BUSD is NativeBaseStrategy {

  address public texo_busd_unused; // just a differentiator for the bytecode

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    //texo-bnb LP
    address underlying = address(0x19F4F3Cdaae6923b387566161a10Dc517a0D11aF);
    address busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    //reward
    address texo = address(0xF1afb5674Bf946458BD1163163F62dE683B07D65);

    NativeBaseStrategy.initializeStrategy(
      _storage,
      underlying,
      _vault,
      address(0xD8980CCdD4096e60bb3198F91d6f79CeEF29369c), // master chef contract
      texo,
      12,  // Pool id
      true // is LP asset
    );
    pancakeswapRoutes[busd] = [texo,busd];
  }
}
