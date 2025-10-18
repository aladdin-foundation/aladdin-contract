// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract AgentMarket is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable usdtToken;

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
    error DuplicateAgent();

    struct Agent {
        address agentAddress;
        uint256 ratePerDay; // 每天的收费标准
        string[] skills; // 技能标签
        uint256 reputation; // 声誉积分，可以根据完成的job数量和质量来提升
    }

    struct Employment {
        address user; // 雇主
        address[] agents; // 被雇佣的Agent数组
        uint256 startTime; // 雇佣开始时间
        uint256 duration; // 雇佣持续时间（天）
        uint256 payment; // 报酬金额
        bool isActive; // 雇佣是否处于激活状态
        bool isCompleted; // 雇佣是否已完成
    }

    mapping(address => Agent) public agents;
    mapping(uint256 => Employment) public employments;
    mapping(uint256 => uint256) public employmentBalances;
    uint256 public employmentCounter;

    event AgentRegistered(
        address indexed agentAddress,
        string[] skills,
        uint256 ratePerDay
    );
    event EmploymentCreated(
        uint256 indexed employmentId,
        address indexed user,
        address[] agents,
        uint256 payment
    );
    event EmploymentCompleted(uint256 indexed employmentId, uint256 payment);
    event PaymentReleased(
        uint256 indexed employmentId,
        address[] agents,
        uint256[] amounts
    );

    constructor(address _usdtAddress) Ownable(msg.sender) {
        if (_usdtAddress == address(0)) revert("Invalid token");
        usdtToken = IERC20(_usdtAddress);
    }

    function registerAgent(
        string[] calldata _skills,
        uint256 ratePerDay
    ) external {
        if (agents[msg.sender].agentAddress != address(0))
            revert AlreadyRegistered();
        if (ratePerDay == 0) revert InvalidRate();
        if (_skills.length == 0) revert EmptySkills();

        agents[msg.sender] = Agent({
            agentAddress: msg.sender,
            ratePerDay: ratePerDay,
            skills: _skills,
            reputation: 0
        });
        emit AgentRegistered(msg.sender, _skills, ratePerDay);
    }

    /**
     * Off-Chain协商后，上链建立雇佣关系（锁定报酬）
     * @param agentAddresses 被雇佣的Agent
     * @param duration 雇佣持续时间（天）
     * @param payment 支付金额
     */
    function createEmployment(
        address[] memory agentAddresses,
        uint256 duration,
        uint256 payment
    ) external {
        if (agentAddresses.length == 0 || agentAddresses.length > MAX_AGENTS)
            revert InvalidAgentsLength();
        if (duration == 0) revert InvalidDuration();
        if (payment == 0) revert InvalidPayment();
        for (uint i = 0; i < agentAddresses.length; ++i) {
            address agentAddr = agentAddresses[i];
            for (uint j = i + 1; j < agentAddresses.length; ++j) {
                if (agentAddr == agentAddresses[j]) revert DuplicateAgent();
            }
        }

        uint256 employmentId = ++employmentCounter;
        uint256 totalExpectedCost = 0;
        for (uint i = 0; i < agentAddresses.length; ++i) {
            Agent storage agent = agents[agentAddresses[i]];
            if (agent.agentAddress == address(0)) revert AgentNotRegistered();
            totalExpectedCost += agent.ratePerDay * duration;
        }
        if (payment < totalExpectedCost) revert PaymentTooLow();

        // 锁定资金：从雇主转移 payment 到合约
        usdtToken.safeTransferFrom(msg.sender, address(this), payment);
        employmentBalances[employmentId] = payment;

        employments[employmentId] = Employment({
            user: msg.sender,
            agents: agentAddresses,
            startTime: block.timestamp,
            duration: duration,
            payment: payment,
            isActive: true,
            isCompleted: false
        });

        emit EmploymentCreated(
            employmentId,
            msg.sender,
            agentAddresses,
            payment
        );
    }

    /**
     * 雇员完成工作（按权重 ratePerDay * duration 分配）
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
            agentRates[i] = agent.ratePerDay * emp.duration;
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
            usdtToken.safeTransfer(emp.agents[i], amount);
        }

        employmentBalances[_empId] = 0;
        emp.isCompleted = true;
        emp.isActive = false;

        emit PaymentReleased(_empId, emp.agents, amounts);
        emit EmploymentCompleted(_empId, emp.payment);
    }

    /**
     * 获取Agent详情
     * @param agentAddress Agent地址
     * @return Agent信息
     */
    function getAgent(address agentAddress) public view returns (Agent memory) {
        return agents[agentAddress];
    }
}
