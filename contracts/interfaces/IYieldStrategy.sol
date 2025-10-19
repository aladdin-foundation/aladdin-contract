// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IYieldStrategy {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external returns (uint256);
    function withdrawAll() external returns (uint256);
    function getBalance() external view returns (uint256);
    function getAPR() external view returns (uint256);
    function getAssetToken() external view returns (address);
    function getRewards() external returns (uint256);
}