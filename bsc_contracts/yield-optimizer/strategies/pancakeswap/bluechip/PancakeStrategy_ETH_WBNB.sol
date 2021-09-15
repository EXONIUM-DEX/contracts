//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../../masterchef/PancakeBaseStrategy.sol";

contract PancakeStrategy_ETH_WBNB is PancakeBaseStrategy {
  address public eth_wbnb_unused; // just a differentiator for the bytecode

  constructor() public {}

  function initializeStrategy(address _storage, address _vault) public initializer {
    //CAKE_WBNB LP
    address underlying = address(0x74E4716E431f45807DCF19f284c7aA99F18a4fbc);
    address eth = address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    //reward
    address cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

    PancakeBaseStrategy.initializeStrategy(
      _storage,
      underlying,
      _vault,
      address(0x73feaa1eE314F8c655E354234017bE2193C9E24E), // master chef contract
      cake,
      261, // Pool id
      true // is LP asset
    );
    pancakeswapRoutes[eth] = [cake, wbnb, eth];
    pancakeswapRoutes[wbnb] = [cake, wbnb];
  }
}
