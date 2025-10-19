// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IYieldStrategy.sol";

interface IAaveLendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface IAaveIncentivesController {
    function getRewardsBalance(address[] calldata assets, address user) external view returns (uint256);
    function claimRewards(address[] calldata assets, uint256 amount, address to) external returns (uint256);
}

interface IAToken is IERC20 {
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function getIncentivesController() external view returns (address);
}

contract AaveYieldStrategy is IYieldStrategy, Ownable {
    using SafeERC20 for IERC20;

    // State variables
    IERC20 public immutable assetToken;
    IAToken public immutable aToken;
    IAaveLendingPool public immutable lendingPool;
    IAaveIncentivesController public immutable incentivesController;

    // APR tracking (simplified, should use oracle in production)
    uint256 public estimatedAPR;
    uint256 public lastAPRUpdate;
    uint256 public constant APR_PRECISION = 10000;

    // Events
    event DepositedToAave(uint256 amount, uint256 timestamp);
    event WithdrawnFromAave(uint256 amount, uint256 timestamp);
    event APRUpdated(uint256 newAPR, uint256 timestamp);
    event RewardsClaimed(uint256 amount, uint256 timestamp);

    // Errors
    error InsufficientBalance();
    error WithdrawFailed();
    error DepositFailed();

    constructor(
        address _assetToken,
        address _aToken,
        address _lendingPool
    ) Ownable(msg.sender) {
        if (_assetToken == address(0) || _aToken == address(0) || _lendingPool == address(0)) {
            revert("Invalid addresses");
        }

        assetToken = IERC20(_assetToken);
        aToken = IAToken(_aToken);
        lendingPool = IAaveLendingPool(_lendingPool);

        // Get incentives controller from aToken
        address controllerAddress;
        try aToken.getIncentivesController() returns (address controller) {
            controllerAddress = controller;
        } catch {
            controllerAddress = address(0);
        }
        incentivesController = IAaveIncentivesController(controllerAddress);

        // Set initial APR (should be updated via oracle)
        estimatedAPR = 300; // 3% initial APR
        lastAPRUpdate = block.timestamp;
    }

    /**
     * @notice 存入资产到 Aave
     */
    function deposit(uint256 amount) external override {
        if (amount == 0) revert InsufficientBalance();

        // Transfer tokens from caller to this contract
        assetToken.safeTransferFrom(msg.sender, address(this), amount);

        // Approve Aave lending pool（累计授权避免非零到零再设的兼容性问题）
        assetToken.safeIncreaseAllowance(address(lendingPool), amount);

        // Deposit to Aave
        try lendingPool.deposit(address(assetToken), amount, address(this), 0) {
            emit DepositedToAave(amount, block.timestamp);
        } catch {
            revert DepositFailed();
        }
    }

    /**
     * @notice 从 Aave 取出指定数量资产
     */
    function withdraw(uint256 amount) external override returns (uint256) {
        if (amount == 0) return 0;

        try lendingPool.withdraw(address(assetToken), amount, msg.sender) returns (uint256 withdrawnAmount) {
            emit WithdrawnFromAave(withdrawnAmount, block.timestamp);
            return withdrawnAmount;
        } catch {
            revert WithdrawFailed();
        }
    }

    /**
     * @notice 从 Aave 取出所有资产
     */
    function withdrawAll() external override returns (uint256) {
        uint256 aTokenBalance = aToken.balanceOf(address(this));
        if (aTokenBalance == 0) return 0;

        try lendingPool.withdraw(address(assetToken), aTokenBalance, msg.sender) returns (uint256 withdrawnAmount) {
            emit WithdrawnFromAave(withdrawnAmount, block.timestamp);
            return withdrawnAmount;
        } catch {
            revert WithdrawFailed();
        }
    }

    /**
     * @notice 获取当前余额
     */
    function getBalance() external view override returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    /**
     * @notice 获取 APR
     */
    function getAPR() external view override returns (uint256) {
        return estimatedAPR;
    }

    /**
     * @notice 获取资产代币地址
     */
    function getAssetToken() external view override returns (address) {
        return address(assetToken);
    }

    /**
     * @notice 领取 Aave 奖励
     */
    function getRewards() external override returns (uint256) {
        if (address(incentivesController) == address(0)) return 0;

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        try incentivesController.claimRewards(assets, type(uint256).max, msg.sender) returns (uint256 rewardAmount) {
            emit RewardsClaimed(rewardAmount, block.timestamp);
            return rewardAmount;
        } catch {
            return 0;
        }
    }

    /**
     * @notice 更新 APR (仅限所有者)
     */
    function updateAPR(uint256 newAPR) external onlyOwner {
        if (newAPR != estimatedAPR) {
            estimatedAPR = newAPR;
            lastAPRUpdate = block.timestamp;
            emit APRUpdated(newAPR, block.timestamp);
        }
    }

    /**
     * @notice 获取可领取的奖励数量
     */
    function getPendingRewards() external view returns (uint256) {
        if (address(incentivesController) == address(0)) return 0;

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        try incentivesController.getRewardsBalance(assets, address(this)) returns (uint256 rewards) {
            return rewards;
        } catch {
            return 0;
        }
    }

    /**
     * @notice 获取 Aave 账户数据
     */
    function getAaveAccountData() external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return lendingPool.getUserAccountData(address(this));
    }

    /**
     * @notice 紧急恢复函数 (仅限所有者)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = aToken.balanceOf(address(this));
        if (balance > 0) {
            lendingPool.withdraw(address(assetToken), balance, owner());
        }
    }
}
