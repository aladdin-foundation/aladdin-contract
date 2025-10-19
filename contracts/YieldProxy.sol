// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IYieldStrategy.sol";

contract YieldProxy is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 public constant FEE_PRECISION = 10000;
    uint256 public constant FEE_PERCENTAGE = 100; // 1% fee

    // State variables
    IERC20 public immutable stakingToken; // USDT or other stablecoin
    IYieldStrategy public currentStrategy;

    // User tracking
    mapping(address => uint256) public userDeposits;
    mapping(address => uint256) public lastClaimTime;
    mapping(address => uint256) public userPrincipal; // Track original principal
    uint256 public totalDeposits;
    uint256 public totalPrincipal;

    // Strategy management
    mapping(address => bool) public authorizedStrategies;
    address[] public strategyHistory;
    mapping(address => uint256) public strategyTimestamps;

    // Fee tracking
    uint256 public totalFees;

    // Events
    event Deposited(address indexed user, uint256 amount, uint256 timestamp);
    event Withdrawn(address indexed user, uint256 amount, uint256 yield, uint256 timestamp);
    event YieldClaimed(address indexed user, uint256 yieldAmount, uint256 timestamp);
    event FeeCollected(uint256 amount);
    event StrategyRewardsClaimed(address indexed caller, uint256 amount);
    event StrategyChanged(address indexed oldStrategy, address indexed newStrategy, uint256 timestamp);
    event StrategyAuthorized(address indexed strategy, bool authorized);
    event RewardTokenWithdrawn(address indexed token, address indexed to, uint256 amount);

    // Errors
    error ZeroAmount();
    error InsufficientBalance();
    error InvalidStrategy();
    error TransferFailed();
    error WithdrawFailed();
    error StrategyNotAuthorized();
    error NoActiveStrategy();
    error InsufficientFeeReserve();
    error RewardTokenNotAllowed();

    modifier onlyValidStrategy() {
        if (address(currentStrategy) == address(0)) revert NoActiveStrategy();
        if (!authorizedStrategies[address(currentStrategy)]) revert StrategyNotAuthorized();
        _;
    }

    constructor(address _stakingToken) Ownable(msg.sender) {
        if (_stakingToken == address(0)) revert("Invalid token");
        stakingToken = IERC20(_stakingToken);
    }

    /**
     * @notice 存入稳定币进行质押
     * @param amount 存入数量
     */
    function deposit(uint256 amount) external nonReentrant onlyValidStrategy {
        if (amount == 0) revert ZeroAmount();

        // Transfer tokens from user to this contract
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        userDeposits[msg.sender] += amount;
        userPrincipal[msg.sender] += amount;
        totalDeposits += amount;
        totalPrincipal += amount;
        lastClaimTime[msg.sender] = block.timestamp;

        stakingToken.safeIncreaseAllowance(address(currentStrategy), amount);
        currentStrategy.deposit(amount);

        emit Deposited(msg.sender, amount, block.timestamp);
    }

    /**
     * @notice 取出质押的稳定币
     * @param amount 取出数量
     */
    function withdraw(uint256 amount) external nonReentrant onlyValidStrategy {
        if (amount == 0) revert ZeroAmount();
        if (userDeposits[msg.sender] < amount) revert InsufficientBalance();

        // Claim yield before withdrawal
        _claimYield(msg.sender);

        // Calculate principal portion to withdraw
        uint256 principalPortion = (userPrincipal[msg.sender] * amount) / userDeposits[msg.sender];

        // Update user state
        userDeposits[msg.sender] -= amount;
        userPrincipal[msg.sender] -= principalPortion;
        totalDeposits -= amount;
        totalPrincipal -= principalPortion;

        // Withdraw from strategy
        try currentStrategy.withdraw(amount) returns (uint256 withdrawnAmount) {
            // Transfer tokens to user
            stakingToken.safeTransfer(msg.sender, withdrawnAmount);

            emit Withdrawn(msg.sender, withdrawnAmount, 0, block.timestamp);
        } catch {
            revert WithdrawFailed();
        }
    }

    /**
     * @notice 取出所有质押和收益
     */
    function withdrawAll() external nonReentrant onlyValidStrategy {
        uint256 userDeposit = userDeposits[msg.sender];
        if (userDeposit == 0) revert InsufficientBalance();

        // Claim all yield first
        uint256 yieldAmount = _claimYield(msg.sender);
        uint256 principalAmount = userPrincipal[msg.sender];

        // Update accounting before interacting with策略
        userDeposits[msg.sender] = 0;
        userPrincipal[msg.sender] = 0;
        totalDeposits -= userDeposit;
        totalPrincipal -= principalAmount;

        uint256 withdrawnAmount = 0;
        if (principalAmount > 0) {
            try currentStrategy.withdraw(principalAmount) returns (uint256 amount) {
                withdrawnAmount = amount;
            } catch {
                revert WithdrawFailed();
            }

            if (withdrawnAmount < principalAmount) revert WithdrawFailed();

            stakingToken.safeTransfer(msg.sender, withdrawnAmount);
        }

        emit Withdrawn(msg.sender, withdrawnAmount, yieldAmount, block.timestamp);
    }

    /**
     * @notice 领取收益
     */
    function claimYield() external nonReentrant onlyValidStrategy {
        _claimYield(msg.sender);
    }

    /**
     * @notice 内部函数：领取收益
     */
    function _claimYield(address user) internal returns (uint256) {
        if (userDeposits[user] == 0 || totalDeposits == 0) return 0;

        uint256 totalBalance = currentStrategy.getBalance();
        uint256 userShare = (totalBalance * userDeposits[user]) / totalDeposits;
        uint256 principalAmount = userPrincipal[user];

        if (userShare <= principalAmount) {
            lastClaimTime[user] = block.timestamp;
            return 0;
        }

        uint256 grossYield = userShare - principalAmount;
        uint256 withdrawnAmount;

        try currentStrategy.withdraw(grossYield) returns (uint256 amount) {
            withdrawnAmount = amount;
        } catch {
            return 0;
        }

        if (withdrawnAmount == 0) {
            return 0;
        }

        if (withdrawnAmount < grossYield) {
            grossYield = withdrawnAmount;
        }

        uint256 fee = (grossYield * FEE_PERCENTAGE) / FEE_PRECISION;
        uint256 userYield = grossYield - fee;

        if (userYield > 0) {
            stakingToken.safeTransfer(user, userYield);
        }

        if (fee > 0) {
            totalFees += fee;
        }

        lastClaimTime[user] = block.timestamp;

        if (userYield > 0) {
            emit YieldClaimed(user, userYield, block.timestamp);
        }

        return userYield;
    }

    /**
     * @notice 获取用户的预估收益
     * @param user 用户地址
     * @return 预估收益数量
     */
    function getUserEstimatedYield(address user) external view onlyValidStrategy returns (uint256) {
        if (userDeposits[user] == 0 || totalDeposits == 0) return 0;

        uint256 totalBalance = currentStrategy.getBalance();
        uint256 userShare = (totalBalance * userDeposits[user]) / totalDeposits;

        return userShare > userPrincipal[user] ? userShare - userPrincipal[user] : 0;
    }

    /**
     * @notice 获取用户的 APR
     * @param user 用户地址
     * @return 用户 APR (基点)
     */
    function getUserAPR(address user) external view onlyValidStrategy returns (uint256) {
        if (userDeposits[user] == 0 || lastClaimTime[user] == 0) return 0;
        if (userPrincipal[user] == 0) return 0;

        uint256 timeElapsed = block.timestamp - lastClaimTime[user];
        if (timeElapsed == 0) return 0;

        uint256 estimatedYield = this.getUserEstimatedYield(user);
        uint256 yearlyYield = (estimatedYield * 365 days) / timeElapsed;

        return (yearlyYield * FEE_PRECISION) / userPrincipal[user];
    }

    /**
     * @notice 获取总余额
     * @return 策略中的总余额
     */
    function getTotalBalance() external view onlyValidStrategy returns (uint256) {
        return currentStrategy.getBalance();
    }

    /**
     * @notice 获取当前 APR
     * @return 当前 APR (基点)
     */
    function getCurrentAPR() external view onlyValidStrategy returns (uint256) {
        return currentStrategy.getAPR();
    }

    /**
     * @notice 添加授权策略
     * @param strategy 策略地址
     */
    function authorizeStrategy(address strategy) external onlyOwner {
        if (strategy == address(0)) revert InvalidStrategy();

        authorizedStrategies[strategy] = true;
        emit StrategyAuthorized(strategy, true);
    }

    /**
     * @notice 移除授权策略
     * @param strategy 策略地址
     */
    function revokeStrategy(address strategy) external onlyOwner {
        authorizedStrategies[strategy] = false;
        emit StrategyAuthorized(strategy, false);
    }

    /**
     * @notice 切换策略 (需要先从旧策略取出所有资金)
     * @param newStrategy 新策略地址
     */
    function switchStrategy(address newStrategy) external onlyOwner nonReentrant {
        if (!authorizedStrategies[newStrategy]) revert StrategyNotAuthorized();

        address oldStrategy = address(currentStrategy);

        if (IYieldStrategy(newStrategy).getAssetToken() != address(stakingToken)) {
            revert InvalidStrategy();
        }

        uint256 reallocateAmount = 0;
        if (oldStrategy != address(0)) {
            try currentStrategy.withdrawAll() returns (uint256 withdrawnAmount) {
                reallocateAmount = withdrawnAmount;
            } catch {
                revert WithdrawFailed();
            }

            stakingToken.forceApprove(oldStrategy, 0);
        }

        currentStrategy = IYieldStrategy(newStrategy);
        strategyHistory.push(newStrategy);
        strategyTimestamps[newStrategy] = block.timestamp;

        if (reallocateAmount > 0) {
            stakingToken.safeIncreaseAllowance(newStrategy, reallocateAmount);
            currentStrategy.deposit(reallocateAmount);
        }

        emit StrategyChanged(oldStrategy, newStrategy, block.timestamp);
    }

    /**
     * @notice 领取协议奖励 (来自策略)
     */
    function claimRewards() external nonReentrant onlyValidStrategy {
        try currentStrategy.getRewards() returns (uint256 rewardAmount) {
            if (rewardAmount > 0) {
                emit StrategyRewardsClaimed(msg.sender, rewardAmount);
            }
        } catch {
            // ignore失败，等待下次
        }
    }

    /**
     * @notice 管理员提取手续费
     */
    function withdrawFees() external onlyOwner {
        uint256 feesToWithdraw = totalFees;
        if (feesToWithdraw == 0) return;

        uint256 contractBalance = stakingToken.balanceOf(address(this));
        if (contractBalance < feesToWithdraw) revert InsufficientFeeReserve();

        totalFees = 0;
        stakingToken.safeTransfer(owner(), feesToWithdraw);
        emit FeeCollected(feesToWithdraw);
    }

    /**
     * @notice 紧急提取函数
     */
    function emergencyWithdraw() external onlyOwner {
        if (address(currentStrategy) != address(0)) {
            try currentStrategy.withdrawAll() returns (uint256 amount) {
                stakingToken.safeTransfer(owner(), amount);
            } catch {
                // Emergency withdrawal failed
            }
        }
    }

    /**
     * @notice 获取策略历史
     * @return 历史策略地址数组
     */
    function getStrategyHistory() external view returns (address[] memory) {
        return strategyHistory;
    }

    function withdrawRewardToken(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (token == address(stakingToken)) revert RewardTokenNotAllowed();
        if (to == address(0)) revert InvalidStrategy();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(to, amount);
        emit RewardTokenWithdrawn(token, to, amount);
    }
}
