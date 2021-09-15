//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../../masterchef/PancakeBaseStrategy.sol";

contract PancakeStrategy_USDC_BUSD is PancakeBaseStrategy {
    address public usdc_busd_unused; // just a differentiator for the bytecode

    constructor() public {}

    function initializeStrategy(address _storage, address _vault)
        public
        initializer
    {
        //link-bnb LP
        address underlying = address(
            0x2354ef4DF11afacb85a5C7f98B624072ECcddbB1
        );
        address busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
        address usdc = address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
        address wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        //reward
        address cake = address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);

        PancakeBaseStrategy.initializeStrategy(
            _storage,
            underlying,
            _vault,
            address(0x73feaa1eE314F8c655E354234017bE2193C9E24E), // master chef contract
            cake,
            283, // Pool id
            true // is LP asset
        );
        pancakeswapRoutes[busd] = [cake, wbnb, busd];
        pancakeswapRoutes[usdc] = [cake, wbnb, usdc];
    }
}
