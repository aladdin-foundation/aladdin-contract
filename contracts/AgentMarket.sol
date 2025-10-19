// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRewardManager {
    function claimRegistrationReward(address agent) external;
    function claimCompletionReward(uint256 employmentId, address[] calldata agents) external;
}

contract AgentMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable usdtToken;
    IRewardManager public rewardManager;

    uint256 public feePercentage = 200; // 2% fee (200 basis points)
    uint256 public constant FEE_PRECISION = 10000;
    uint256 public constant MAX_AGENTS = 20; // Agent上限常量

    error AlreadyRegistered();
    error InvalidRate();
    error EmptySkills();
    error NoAgentsSpecified();
    error InvalidDuration();
    error InvalidPayment();
    error AgentNotRegistered();
    error PaymentTooLow();
    error InvalidAgentsLength();
    error NoPermission();
    error NotActive();
    error AlreadyCompleted();
    error NoValidRates();
    error TransferFailed();
    error InsufficientBalance();
    error CannotHireOwnAgent();
    error InvalidRecipient();

    struct Agent {
        uint256 id; // 唯一ID
        address owner; // Agent拥有者地址
        uint256 ratePer; // 每天的收费标准
        string[] skills; // 技能标签
        uint256 reputation; // 声誉积分，可以根据完成的job数量和质量来提升
    }

    struct Employment {
        address user; // 雇主
        uint256[] agents; // 被雇佣的Agent数组
        uint256 startTime; // 雇佣开始时间
        uint256 duration; // 雇佣持续时间（天）
        uint256 payment; // 报酬金额
        bool isActive; // 雇佣是否处于激活状态
        bool isCompleted; // 雇佣是否已完成
    }

    mapping(uint256 => Agent) public agents; // agentId => Agent
    mapping(address => uint256[]) public ownerAgents; // owner address => agentIds
    mapping(uint256 => Employment) public employments;
    mapping(uint256 => uint256) public employmentBalances;
    uint256 public agentCounter;
    uint256 public employmentCounter;

    // 新增：用户托管余额
    mapping(address => uint256) public userBalances;
    event Deposited(address indexed user, uint256 amount);

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        string[] skills,
        uint256 ratePer
    );
    event EmploymentCreated(
        uint256 indexed employmentId,
        address indexed user,
        uint256[] agents,
        uint256 payment
    );
    event EmploymentCompleted(uint256 indexed employmentId, uint256 payment);
    event PaymentReleased(
        uint256 indexed employmentId,
        address[] agents,
        uint256[] amounts
    );
    event EmploymentEnded(uint256 indexed employmentId, address indexed recipient, uint256 amount);

    constructor(address _usdtAddress, address _rewardManager) Ownable(msg.sender) {
        if (_usdtAddress == address(0)) revert("Invalid token");
        usdtToken = IERC20(_usdtAddress);
        rewardManager = IRewardManager(_rewardManager);
    }

    /**
     * @notice 更新 RewardManager 地址（仅 owner）
     */
    function setRewardManager(address _rewardManager) external onlyOwner {
        if (_rewardManager == address(0)) revert("Invalid address");
        rewardManager = IRewardManager(_rewardManager);
    }

    function registerAgent(
        string[] calldata _skills,
        uint256 ratePer
    ) external {
        if (ratePer == 0) revert InvalidRate();
        if (_skills.length == 0) revert EmptySkills();

        uint256 agentId = ++agentCounter;

        Agent storage a = agents[agentId];
        a.id = agentId;
        a.owner = msg.sender;
        a.ratePer = ratePer;

        // Copy skills from calldata to storage explicitly
        for (uint256 i = 0; i < _skills.length; i++) {
            a.skills.push(_skills[i]);
        }

        a.reputation = 0;

        ownerAgents[msg.sender].push(agentId);

        emit AgentRegistered(agentId, msg.sender, _skills, ratePer);

        // 发放注册奖励
        if (address(rewardManager) != address(0)) {
            rewardManager.claimRegistrationReward(msg.sender);
        }
    }

    // 1) 充值（需要先对 usdt.approve(market, amount)）
    function deposit(uint256 amount) external {
        if (amount == 0) revert InvalidPayment();
        usdtToken.safeTransferFrom(msg.sender, address(this), amount);
        userBalances[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /**
     * Off-Chain协商后，上链建立雇佣关系（锁定报酬）
     * @param payer 扣款账户（托管余额从这个地址中扣）
     * @param agentIds 被雇佣的Agent
     * @param duration 雇佣持续时间（天）
     * @param payment 支付金额
     */
    function createEmployment(
        address payer,
        uint256[] memory agentIds,
        uint256 duration,
        uint256 payment
    ) external {
        if (agentIds.length == 0 || agentIds.length > MAX_AGENTS)
            revert InvalidAgentsLength();
        if (duration == 0) revert InvalidDuration();
        if (payment == 0) revert InvalidPayment();
        if (payer == address(0)) revert InvalidPayment();
        if (userBalances[payer] < payment) revert InsufficientBalance();

        uint256 employmentId = ++employmentCounter;
        uint256 totalExpectedCost = 0;
        uint256 length = agentIds.length;

        for (uint i = 0; i < length; ++i) {
            uint256 aid = agentIds[i];
            Agent storage agent = agents[aid];
            if (agent.owner == address(0)) revert AgentNotRegistered();

            // 防止自雇佣（防止刷奖励）
            if (agent.owner == payer) revert CannotHireOwnAgent();

            unchecked {
                totalExpectedCost += agent.ratePer * duration;
            }
        }
        if (payment < totalExpectedCost) revert PaymentTooLow();

        // 锁定资金：从用户托管余额扣除对应金额
        userBalances[payer] -= payment;
        employmentBalances[employmentId] = payment;

        employments[employmentId] = Employment({
            user: payer,
            agents: agentIds,
            startTime: block.timestamp,
            duration: duration,
            payment: payment,
            isActive: true,
            isCompleted: false
        });

        emit EmploymentCreated(employmentId, payer, agentIds, payment);
    }

    /**
     * 雇员完成工作（按权重 ratePer * duration 分配）
     * @param _empId 雇佣ID
     */
    function completeEngagement(uint256 _empId) external nonReentrant {
        Employment storage emp = employments[_empId];
        if (msg.sender != emp.user && msg.sender != owner())
            revert NoPermission();
        if (!emp.isActive) revert NotActive();
        if (emp.isCompleted) revert AlreadyCompleted();

        uint256 numAgents = emp.agents.length;
        uint256 totalFee = (emp.payment * feePercentage) / FEE_PRECISION;
        uint256 totalAgentShare = emp.payment - totalFee;

        uint256 sumRates = 0;
        uint256[] memory agentRates = new uint256[](numAgents);
        for (uint i = 0; i < numAgents; ++i) {
            Agent storage agent = agents[emp.agents[i]];
            agentRates[i] = agent.ratePer * emp.duration;
            sumRates += agentRates[i];
        }
        if (sumRates == 0) revert NoValidRates();

        // 先转移手续费给owner
        if (totalFee > 0) {
            usdtToken.safeTransfer(owner(), totalFee);
        }

        uint256 sumBases = 0;
        uint256[] memory amounts = new uint256[](numAgents);
        for (uint i = 0; i < numAgents; ++i) {
            uint256 base = (totalAgentShare * agentRates[i]) / sumRates;
            amounts[i] = base;
            sumBases += base;
        }

        uint256 remainder = totalAgentShare - sumBases;
        for (uint i = 0; i < numAgents && remainder > 0; ++i) {
            amounts[i] += 1;
            remainder -= 1;
        }

        for (uint i = 0; i < numAgents; ++i) {
            uint256 amount = amounts[i];
            if (amount == 0) revert TransferFailed();
            usdtToken.safeTransfer(agents[emp.agents[i]].owner, amount);
        }

        employmentBalances[_empId] = 0;
        emp.isCompleted = true;
        emp.isActive = false;

        address[] memory agentOwners = new address[](numAgents);
        for (uint i = 0; i < numAgents; ++i) {
            agentOwners[i] = agents[emp.agents[i]].owner;
        }
        emit PaymentReleased(_empId, agentOwners, amounts);
        emit EmploymentCompleted(_empId, emp.payment);

        // 发放任务完成奖励
        if (address(rewardManager) != address(0)) {
            rewardManager.claimCompletionReward(_empId, agentOwners);
        }
    }

    /**
     * 获取Agent详情
     * @param agentId AgentId
     * @return Agent信息
     */
    function getAgent(uint256 agentId) public view returns (Agent memory) {
        return agents[agentId];
    }

    /**
     * 获取某地址名下的所有 agentId
     */
    function getOwnerAgents(
        address ownerAddr
    ) external view returns (uint256[] memory) {
        return ownerAgents[ownerAddr];
    }

    /**
     * 结束合同并支付金额给agent的owner
     * @param _empId 合同ID
     * @param recipient 接收的地址（agent的owner地址）
     */
    function completeEngagementAndPay(
        uint256 _empId,
        address recipient
    ) external nonReentrant {
        Employment storage emp = employments[_empId];
        if (msg.sender != emp.user && msg.sender != owner())
            revert NoPermission();
        if (!emp.isActive) revert NotActive();
        if (emp.isCompleted) revert AlreadyCompleted();
        if (recipient == address(0)) revert InvalidPayment();

        bool isValidRecipient = false;
        for (uint i = 0; i < emp.agents.length; ++i) {
            if (agents[emp.agents[i]].owner == recipient) {
                isValidRecipient = true;
                break;
            }
        }
        if (!isValidRecipient) revert InvalidRecipient();

        uint256 balance = employmentBalances[_empId];
        if (balance == 0) revert InsufficientBalance();

        // 删除合同记录
        delete employments[_empId];
        employmentBalances[_empId] = 0;

        // 转账资金
        usdtToken.safeTransfer(recipient, balance);
        emit EmploymentEnded(_empId, recipient, balance); // 需要在合约中定义这个事件
    }
}
