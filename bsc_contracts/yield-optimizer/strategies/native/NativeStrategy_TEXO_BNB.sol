//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../masterchef/NativeBaseStrategy.sol";

contract NativeStrategy_TEXO_BNB is NativeBaseStrategy {

  address public texo_bnb_unused; // just a differentiator for the bytecode

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    //texo-bnb LP
    address underlying = address(0x572274F3f1a2d4016d85EB1BA2c4DA671805218e);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    //reward
    address texo = address(0xF1afb5674Bf946458BD1163163F62dE683B07D65);

    NativeBaseStrategy.initializeStrategy(
      _storage,
      underlying,
      _vault,
      address(0xD8980CCdD4096e60bb3198F91d6f79CeEF29369c), // master chef contract
      texo,
      11,  // Pool id
      true // is LP asset
    );
    pancakeswapRoutes[wbnb] = [texo, wbnb];
  }
}
