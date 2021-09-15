//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../../masterchef/PancakeBaseStrategy.sol";

contract PancakeStrategy_CAKE_WBNB is PancakeBaseStrategy {
    address public cake_wbnb_unused; // just a differentiator for the bytecode

    constructor() public {}

    function initializeStrategy(address _storage, address _vault)
        public
        initializer
    {
        //CAKE_WBNB LP
        address underlying = address(
            0x0eD7e52944161450477ee417DE9Cd3a859b14fD0
        );
        address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        //reward
        address cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

        PancakeBaseStrategy.initializeStrategy(
            _storage,
            underlying,
            _vault,
            address(0x73feaa1eE314F8c655E354234017bE2193C9E24E), // master chef contract
            cake,
            251, // Pool id
            true // is LP asset
        );
        pancakeswapRoutes[wbnb] = [cake, wbnb];
    }
}
