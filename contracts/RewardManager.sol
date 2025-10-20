// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RewardManager
 * @notice 管理 AladdinToken 的奖励分发
 * @dev MVP 版本：注册和完成任务都发放固定数量代币，后续可扩展为复杂计算
 */
contract RewardManager is Ownable, ReentrancyGuard {
    // ALD 代币合约
    IERC20 public immutable aladdinToken;
    // 授权调用者
    address public agentMarket;

    // 奖励配置（可由 owner 调整）
    uint256 public registrationReward = 500 * 10**18;  // 注册奖励 500 ALD
    uint256 public completionReward = 500 * 10**18;    // 完成任务奖励 500 ALD

    // 防刷机制，地址 → 是否已领取注册奖励
    mapping(address => bool) public hasClaimedRegistration;
    // 雇佣ID → 是否已领取完成
    mapping(uint256 => bool) public hasClaimedEmployment; // employmentId => claimed

    // 统计数据，
    uint256 public totalRewardsDistributed;
    uint256 public totalRegistrationRewards;
    uint256 public totalCompletionRewards;

    error OnlyAgentMarket();
    error AlreadyClaimed();
    error InsufficientRewardBalance();
    error InvalidAmount();

    event RegistrationRewardClaimed(address indexed agent, uint256 amount);
    event CompletionRewardClaimed(uint256 indexed employmentId, address indexed agent, uint256 amount);
    event RewardConfigUpdated(uint256 registrationReward, uint256 completionReward);
    event AgentMarketUpdated(address indexed oldMarket, address indexed newMarket);

    modifier onlyAgentMarket() {
        if (msg.sender != agentMarket) revert OnlyAgentMarket();
        _;
    }

    constructor(address _aladdinToken, address _agentMarket) Ownable(msg.sender) {
        if (_aladdinToken == address(0) || _agentMarket == address(0)) {
            revert("Invalid address");
        }
        aladdinToken = IERC20(_aladdinToken);
        agentMarket = _agentMarket;
    }

    /**
     * @notice 发放注册奖励（由 AgentMarket 调用）
     * @param agent Agent 所有者地址
     */
    function claimRegistrationReward(address agent) external onlyAgentMarket nonReentrant {
        if (hasClaimedRegistration[agent]) revert AlreadyClaimed();
        if (aladdinToken.balanceOf(address(this)) < registrationReward) {
            revert InsufficientRewardBalance();
        }

        hasClaimedRegistration[agent] = true;
        totalRegistrationRewards += registrationReward;
        totalRewardsDistributed += registrationReward;

        aladdinToken.transfer(agent, registrationReward);

        emit RegistrationRewardClaimed(agent, registrationReward);
    }

    /**
     * @notice 发放任务完成奖励（由 AgentMarket 调用）
     * @param employmentId 雇佣关系 ID
     * @param agents 参与的 Agent 地址数组
     */
    function claimCompletionReward(
        uint256 employmentId,
        address[] calldata agents
    ) external onlyAgentMarket nonReentrant {
        if (hasClaimedEmployment[employmentId]) revert AlreadyClaimed();

        uint256 totalReward = completionReward * agents.length;
        if (aladdinToken.balanceOf(address(this)) < totalReward) {
            revert InsufficientRewardBalance();
        }

        hasClaimedEmployment[employmentId] = true;
        totalCompletionRewards += totalReward;
        totalRewardsDistributed += totalReward;

        // 给每个 Agent 发放奖励
        for (uint256 i = 0; i < agents.length; i++) {
            aladdinToken.transfer(agents[i], completionReward);
            emit CompletionRewardClaimed(employmentId, agents[i], completionReward);
        }
    }

    /**
     * @notice 更新奖励配置（仅 owner）
     * @param _registrationReward 新的注册奖励
     * @param _completionReward 新的完成奖励
     */
    function setRewardAmounts(
        uint256 _registrationReward,
        uint256 _completionReward
    ) external onlyOwner {
        if (_registrationReward == 0 || _completionReward == 0) revert InvalidAmount();

        registrationReward = _registrationReward;
        completionReward = _completionReward;

        emit RewardConfigUpdated(_registrationReward, _completionReward);
    }

    /**
     * @notice 更新 AgentMarket 地址（仅 owner）
     * @param _newMarket 新的 AgentMarket 地址
     */
    function setAgentMarket(address _newMarket) external onlyOwner {
        if (_newMarket == address(0)) revert("Invalid address");

        address oldMarket = agentMarket;
        agentMarket = _newMarket;

        emit AgentMarketUpdated(oldMarket, _newMarket);
    }

    /**
     * @notice 提取剩余代币（仅 owner，用于紧急情况）
     * @param to 接收地址
     * @param amount 提取数量
     */
    function withdrawRemaining(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert("Invalid address");
        if (amount == 0) revert InvalidAmount();

        uint256 balance = aladdinToken.balanceOf(address(this));
        if (amount > balance) revert InsufficientRewardBalance();

        aladdinToken.transfer(to, amount);
    }

    /**
     * @notice 获取当前奖励池余额
     */
    function getRewardPoolBalance() external view returns (uint256) {
        return aladdinToken.balanceOf(address(this));
    }
}
