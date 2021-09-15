//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

import "../../../masterchef/PancakeBaseStrategy.sol";

contract PancakeStrategy_USDT_USDC is PancakeBaseStrategy {
    address public usdt_usdc_unused; // just a differentiator for the bytecode

    constructor() public {}

    function initializeStrategy(address _storage, address _vault)
        public
        initializer
    {
        //link-bnb LP
        address underlying = address(
            0xEc6557348085Aa57C72514D67070dC863C0a5A8c
        );
        address usdt = address(0x55d398326f99059fF775485246999027B3197955);
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
            423, // Pool id
            true // is LP asset
        );
        pancakeswapRoutes[usdt] = [cake, wbnb, usdt];
        pancakeswapRoutes[usdc] = [cake, wbnb, usdc];
    }
}
