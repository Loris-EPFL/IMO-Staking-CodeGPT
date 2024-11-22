// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IABalancer {
    event SetBalancerVault(address newVault);
    event SetBalancerPoolId(bytes32 newPoolId);
    event SetImoAddress(address newAddress);

    function setImoAddress(address _newAddress) external;
    function setBalancerVault(address _vault) external;
    function setBalancerPoolId(bytes32 _poolId) external;
    function setBalancerQueries(address _balancerQueries) external;
    function resetBalancerAllowance() external;
    function removeBalancerAllowance() external;
    function ethToImo(uint256 amount, uint256 imoOutMin, address sender, address receiver) external returns (uint256 amountOutCalculated);
    function queryJoinImoPool(uint256 EthAmount, uint256 ImoAmount, address sender, address receiver) external returns (uint256 amountOutCalculated);
    function joinImoPool(uint256 EthAmount, uint256 ImoAmount, address sender, address receiver) external;
    function joinImoPoolOnlyEth(uint256 EthAmount, address sender, address receiver) external;
    function getUserImoBalanceFromPool(uint256 BPTbalanceofUser) external view returns (uint256);
}
