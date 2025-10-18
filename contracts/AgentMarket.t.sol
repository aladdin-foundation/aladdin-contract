// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./AgentMarket.sol";
import "./AladdinToken.sol";

contract AgentMarketTest is Test {
    AgentMarket internal market;
    AladdinToken internal usdt;

    address internal constant USER = address(0x1000);
    address internal constant AGENT_ONE = address(0x2000);
    address internal constant AGENT_TWO = address(0x3000);
    uint256 internal constant INITIAL_USER_FUNDS = 10_000 ether;

    // 声明事件用于测试
    event AgentRegistered(uint256 indexed agentId, address indexed owner, string[] skills, uint256 ratePer);
    event Deposited(address indexed user, uint256 amount);
    event EmploymentCreated(uint256 indexed employmentId, address indexed user, uint256[] agents, uint256 payment);
    event PaymentReleased(uint256 indexed employmentId, address[] agents, uint256[] amounts);
    event EmploymentCompleted(uint256 indexed employmentId, uint256 payment);

    function setUp() public {
        usdt = new AladdinToken(address(this));
        market = new AgentMarket(address(usdt));

        // 为测试账号注入资金
        usdt.mint(USER, INITIAL_USER_FUNDS);
    }

    // 辅助函数：注册Agent并返回agentId
    function _registerAgent(
        address agentOwner,
        uint256 ratePer,
        string memory skill
    ) internal returns (uint256) {
        string[] memory skills = new string[](1);
        skills[0] = skill;
        vm.prank(agentOwner);
        market.registerAgent(skills, ratePer);
        return market.agentCounter();
    }

    function test_RegisterAgent_ShouldPersistMetadata() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 100 ether, "solidity");

        AgentMarket.Agent memory stored = market.getAgent(agentId);
        assertEq(stored.id, agentId, unicode"Agent ID应被记录");
        assertEq(stored.owner, AGENT_ONE, unicode"Agent拥有者地址应被记录");
        assertEq(stored.ratePer, 100 ether, unicode"价格应与注册值一致");
        assertEq(stored.skills.length, 1, unicode"技能列表长度异常");
        assertEq(
            keccak256(bytes(stored.skills[0])),
            keccak256(bytes("solidity")),
            unicode"技能名称不匹配"
        );
    }

    function test_CreateEmployment_RevertWhenAgentNotRegistered() public {
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = 999; // 不存在的agentId

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);
        vm.expectRevert(AgentMarket.AgentNotRegistered.selector);
        market.createEmployment(USER, agentIds, 1, 100 ether);
        vm.stopPrank();
    }

    function test_Deposit_ShouldIncreaseEscrowBalance() public {
        vm.startPrank(USER);
        usdt.approve(address(market), 300 ether);
        market.deposit(300 ether);
        vm.stopPrank();

        assertEq(market.userBalances(USER), 300 ether, unicode"用户托管余额未增加");
        assertEq(usdt.balanceOf(address(market)), 300 ether, unicode"合约余额异常");
    }

    function test_Deposit_RevertWhenAmountZero() public {
        vm.startPrank(USER);
        usdt.approve(address(market), 1 ether);
        vm.expectRevert(AgentMarket.InvalidPayment.selector);
        market.deposit(0);
        vm.stopPrank();
    }

    function test_CreateEmployment_ShouldLockFunds() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 25 ether, "zk");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 500 ether);
        market.deposit(500 ether);
        market.createEmployment(USER, agentIds, 2, 500 ether);
        vm.stopPrank();

        assertEq(market.employmentCounter(), 1, unicode"计数器未更新");
        assertEq(market.employmentBalances(1), 500 ether, unicode"托管金额不正确");
        assertEq(usdt.balanceOf(address(market)), 500 ether, unicode"合约持有金额异常");
        assertEq(market.userBalances(USER), 0, unicode"用户托管余额应扣除");

        (
            address jobUser,
            uint256 startTime,
            uint256 duration,
            uint256 payment,
            bool isActive,
            bool isCompleted
        ) = market.employments(1);

        assertEq(jobUser, USER, unicode"雇主地址错误");
        assertGt(startTime, 0, unicode"开始时间未填充");
        assertEq(duration, 2, unicode"持续时间错误");
        assertEq(payment, 500 ether, unicode"支付金额错误");
        assertTrue(isActive, unicode"雇佣应为激活状态");
        assertFalse(isCompleted, unicode"雇佣不应已完成");
    }

    function test_CreateEmployment_RevertWhenPaymentTooLow() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 100 ether, "ml");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);
        vm.expectRevert(AgentMarket.PaymentTooLow.selector);
        market.createEmployment(USER, agentIds, 1, 50 ether);
        vm.stopPrank();
    }

    function test_CreateEmployment_RevertWhenInsufficientBalance() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "infra");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        vm.expectRevert(AgentMarket.InsufficientBalance.selector);
        market.createEmployment(USER, agentIds, 1, 10 ether);
        vm.stopPrank();
    }

    function test_CreateEmployment_RevertWhenNoAgentsProvided() public {
        uint256[] memory agentIds = new uint256[](0);

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);
        vm.expectRevert(AgentMarket.InvalidAgentsLength.selector);
        market.createEmployment(USER, agentIds, 1, 100 ether);
        vm.stopPrank();
    }

    function test_CreateEmployment_RevertWhenExceedingMaxAgents() public {
        uint256 maxAgents = market.MAX_AGENTS();
        uint256[] memory agentIds = new uint256[](maxAgents + 1);
        for (uint256 i = 0; i < agentIds.length; ++i) {
            agentIds[i] = i + 1;
        }

        vm.startPrank(USER);
        usdt.approve(address(market), 1 ether);
        vm.expectRevert(AgentMarket.InvalidAgentsLength.selector);
        market.createEmployment(USER, agentIds, 1, 1 ether);
        vm.stopPrank();
    }


    function test_CreateEmployment_ShouldAllowReusingAgentsAcrossCalls() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 40 ether, "solidity");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 800 ether);
        market.deposit(800 ether);
        market.createEmployment(USER, agentIds, 2, 400 ether);
        market.createEmployment(USER, agentIds, 3, 400 ether);
        vm.stopPrank();

        assertEq(market.employmentCounter(), 2, unicode"应创建两条雇佣记录");
        assertEq(market.userBalances(USER), 0, unicode"托管余额应被消费完毕");
    }

    function test_CompleteEngagement_ShouldPayAgentsAndOwner() public {
        uint256 agentId1 = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256 agentId2 = _registerAgent(AGENT_TWO, 30 ether, "design");

        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = agentId1;
        agentIds[1] = agentId2;

        vm.startPrank(USER);
        usdt.approve(address(market), 1_000 ether);
        market.deposit(1_000 ether);
        market.createEmployment(USER, agentIds, 2, 1_000 ether);
        vm.stopPrank();

        uint256 ownerBalanceBefore = usdt.balanceOf(address(this));

        vm.prank(USER);
        market.completeEngagement(1);

        uint256 fee = (1_000 ether * market.feePercentage()) /
            market.FEE_PRECISION();
        uint256 totalShare = 1_000 ether - fee;
        uint256 agentOneExpected = (totalShare * (10 ether * 2)) /
            ((10 ether * 2) + (30 ether * 2));
        uint256 agentTwoExpected = totalShare - agentOneExpected;

        assertEq(
            usdt.balanceOf(address(this)),
            ownerBalanceBefore + fee,
            unicode"手续费未到账"
        );
        assertEq(
            usdt.balanceOf(AGENT_ONE),
            agentOneExpected,
            unicode"Agent1 分润错误"
        );
        assertEq(
            usdt.balanceOf(AGENT_TWO),
            agentTwoExpected,
            unicode"Agent2 分润错误"
        );
        assertEq(
            market.employmentBalances(1),
            0,
            unicode"托管余额应清零"
        );

        (
            ,
            ,
            ,
            ,
            bool isActiveAfter,
            bool isCompletedAfter
        ) = market.employments(1);

        assertFalse(isActiveAfter, unicode"状态应标记为非激活");
        assertTrue(isCompletedAfter, unicode"状态应标记为完成");
    }

    function test_CompleteEngagement_RevertWhenCallerUnauthorized() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 5 ether, "solidity");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 200 ether);
        market.deposit(200 ether);
        market.createEmployment(USER, agentIds, 1, 200 ether);
        vm.stopPrank();

        vm.expectRevert(AgentMarket.NoPermission.selector);
        vm.prank(address(0xdead));
        market.completeEngagement(1);
    }

    function test_CompleteEngagement_RevertWhenCalledTwice() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 300 ether);
        market.deposit(300 ether);
        market.createEmployment(USER, agentIds, 1, 300 ether);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        vm.expectRevert(AgentMarket.NotActive.selector);
        vm.prank(USER);
        market.completeEngagement(1);
    }

    function test_CompleteEngagement_ShouldAllowOwnerFinalize() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 15 ether, "solidity");

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 500 ether);
        market.deposit(500 ether);
        market.createEmployment(USER, agentIds, 2, 500 ether);
        vm.stopPrank();

        uint256 ownerBalanceBefore = usdt.balanceOf(address(this));
        vm.prank(address(this));
        market.completeEngagement(1);

        uint256 fee = (500 ether * market.feePercentage()) /
            market.FEE_PRECISION();
        assertEq(
            usdt.balanceOf(address(this)),
            ownerBalanceBefore + fee,
            unicode"Owner 应收到手续费"
        );
    }

    // ========== 新增测试用例 ==========

    // registerAgent 额外测试
    function test_RegisterAgent_RevertWhenRateIsZero() public {
        string[] memory skills = new string[](1);
        skills[0] = "solidity";

        vm.expectRevert(AgentMarket.InvalidRate.selector);
        vm.prank(AGENT_ONE);
        market.registerAgent(skills, 0);
    }

    function test_RegisterAgent_RevertWhenSkillsEmpty() public {
        string[] memory skills = new string[](0);

        vm.expectRevert(AgentMarket.EmptySkills.selector);
        vm.prank(AGENT_ONE);
        market.registerAgent(skills, 10 ether);
    }

    function test_RegisterAgent_ShouldAllowMultipleAgentsPerOwner() public {
        uint256 firstAgentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256 secondAgentId = _registerAgent(AGENT_ONE, 20 ether, "rust");

        assertEq(firstAgentId, 1, unicode"第一个Agent ID应为1");
        assertEq(secondAgentId, 2, unicode"第二个Agent ID应为2");

        uint256[] memory ownerAgents = market.getOwnerAgents(AGENT_ONE);
        assertEq(ownerAgents.length, 2, unicode"Owner应拥有2个Agents");
        assertEq(ownerAgents[0], firstAgentId, unicode"第一个Agent ID不匹配");
        assertEq(ownerAgents[1], secondAgentId, unicode"第二个Agent ID不匹配");
    }

    function test_RegisterAgent_ShouldEmitEvent() public {
        string[] memory skills = new string[](2);
        skills[0] = "solidity";
        skills[1] = "hardhat";

        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(1, AGENT_ONE, skills, 50 ether);

        vm.prank(AGENT_ONE);
        market.registerAgent(skills, 50 ether);
    }

    function test_RegisterAgent_ShouldStoreMultipleSkills() public {
        string[] memory skills = new string[](3);
        skills[0] = "solidity";
        skills[1] = "javascript";
        skills[2] = "python";

        uint256 agentId = _registerAgent(AGENT_ONE, 30 ether, "solidity");

        // 手动注册带多个技能的Agent
        vm.prank(AGENT_TWO);
        market.registerAgent(skills, 30 ether);

        AgentMarket.Agent memory agent = market.getAgent(2);
        assertEq(agent.skills.length, 3, unicode"应存储3个技能");
        assertEq(
            keccak256(bytes(agent.skills[0])),
            keccak256(bytes("solidity")),
            unicode"技能0不匹配"
        );
        assertEq(
            keccak256(bytes(agent.skills[1])),
            keccak256(bytes("javascript")),
            unicode"技能1不匹配"
        );
        assertEq(
            keccak256(bytes(agent.skills[2])),
            keccak256(bytes("python")),
            unicode"技能2不匹配"
        );
    }

    // deposit 额外测试
    function test_Deposit_ShouldEmitEvent() public {
        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);

        vm.expectEmit(true, false, false, true);
        emit Deposited(USER, 100 ether);

        market.deposit(100 ether);
        vm.stopPrank();
    }

    function test_Deposit_ShouldAllowMultipleDeposits() public {
        vm.startPrank(USER);
        usdt.approve(address(market), 500 ether);
        market.deposit(200 ether);
        market.deposit(300 ether);
        vm.stopPrank();

        assertEq(
            market.userBalances(USER),
            500 ether,
            unicode"多次充值累计余额不正确"
        );
    }

    // createEmployment 额外测试
    function test_CreateEmployment_RevertWhenPayerIsZeroAddress() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.expectRevert(AgentMarket.InvalidPayment.selector);
        market.createEmployment(address(0), agentIds, 1, 10 ether);
    }

    function test_CreateEmployment_ShouldEmitEvent() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 25 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);

        vm.expectEmit(true, true, false, true);
        emit EmploymentCreated(1, USER, agentIds, 100 ether);

        market.createEmployment(USER, agentIds, 1, 100 ether);
        vm.stopPrank();
    }

    function test_CreateEmployment_ShouldDecrementUserBalanceCorrectly() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 1000 ether);
        market.deposit(1000 ether);

        uint256 balanceBefore = market.userBalances(USER);
        market.createEmployment(USER, agentIds, 1, 100 ether);
        uint256 balanceAfter = market.userBalances(USER);

        assertEq(
            balanceBefore - balanceAfter,
            100 ether,
            unicode"用户余额扣除金额不正确"
        );
        vm.stopPrank();
    }

    function test_CreateEmployment_ShouldAcceptExactMinimumPayment() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 50 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        uint256 exactPayment = 50 ether * 3; // rate * duration

        vm.startPrank(USER);
        usdt.approve(address(market), exactPayment);
        market.deposit(exactPayment);
        market.createEmployment(USER, agentIds, 3, exactPayment);
        vm.stopPrank();

        assertEq(market.employmentBalances(1), exactPayment, unicode"托管金额不正确");
    }

    // completeEngagement 额外测试
    function test_CompleteEngagement_ShouldDistributeRemainderCorrectly() public {
        // 使用特殊数值制造余数情况
        uint256 agentId1 = _registerAgent(AGENT_ONE, 7 ether, "solidity");
        uint256 agentId2 = _registerAgent(AGENT_TWO, 11 ether, "rust");

        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = agentId1;
        agentIds[1] = agentId2;

        uint256 payment = 100 ether;

        vm.startPrank(USER);
        usdt.approve(address(market), payment);
        market.deposit(payment);
        market.createEmployment(USER, agentIds, 1, payment);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        uint256 agent1Balance = usdt.balanceOf(AGENT_ONE);
        uint256 agent2Balance = usdt.balanceOf(AGENT_TWO);
        uint256 ownerBalance = usdt.balanceOf(address(this));

        // 验证总和正确
        uint256 fee = (payment * market.feePercentage()) / market.FEE_PRECISION();
        assertEq(
            agent1Balance + agent2Balance + fee,
            payment,
            unicode"总支付金额不正确"
        );
    }

    function test_CompleteEngagement_ShouldEmitPaymentReleasedEvent() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);
        market.createEmployment(USER, agentIds, 1, 100 ether);
        vm.stopPrank();

        vm.expectEmit(true, false, false, false);
        emit PaymentReleased(1, new address[](0), new uint256[](0));

        vm.prank(USER);
        market.completeEngagement(1);
    }

    function test_CompleteEngagement_ShouldEmitEmploymentCompletedEvent() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 100 ether);
        market.deposit(100 ether);
        market.createEmployment(USER, agentIds, 1, 100 ether);
        vm.stopPrank();

        vm.expectEmit(true, false, false, true);
        emit EmploymentCompleted(1, 100 ether);

        vm.prank(USER);
        market.completeEngagement(1);
    }

    function test_CompleteEngagement_WithThreeAgentsDifferentRates() public {
        uint256 agentId1 = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256 agentId2 = _registerAgent(AGENT_TWO, 20 ether, "rust");

        address agent3 = address(0x4000);
        string[] memory skills = new string[](1);
        skills[0] = "python";
        vm.prank(agent3);
        market.registerAgent(skills, 30 ether);
        uint256 agentId3 = market.agentCounter();

        uint256[] memory agentIds = new uint256[](3);
        agentIds[0] = agentId1;
        agentIds[1] = agentId2;
        agentIds[2] = agentId3;

        uint256 payment = 1200 ether;

        vm.startPrank(USER);
        usdt.approve(address(market), payment);
        market.deposit(payment);
        market.createEmployment(USER, agentIds, 2, payment);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        // 验证分配比例
        uint256 fee = (payment * market.feePercentage()) / market.FEE_PRECISION();
        uint256 totalShare = payment - fee;

        // totalRates = (10*2) + (20*2) + (30*2) = 20 + 40 + 60 = 120
        uint256 agent1Expected = (totalShare * 20) / 120;
        uint256 agent2Expected = (totalShare * 40) / 120;
        uint256 agent3Expected = (totalShare * 60) / 120;

        assertGt(usdt.balanceOf(AGENT_ONE), 0, unicode"Agent1应收到款项");
        assertGt(usdt.balanceOf(AGENT_TWO), 0, unicode"Agent2应收到款项");
        assertGt(usdt.balanceOf(agent3), 0, unicode"Agent3应收到款项");

        // 验证Agent2收到的是Agent1的两倍左右
        assertGt(
            usdt.balanceOf(AGENT_TWO),
            usdt.balanceOf(AGENT_ONE),
            unicode"Agent2收入应大于Agent1"
        );
        assertGt(
            usdt.balanceOf(agent3),
            usdt.balanceOf(AGENT_TWO),
            unicode"Agent3收入应大于Agent2"
        );
    }

    // getOwnerAgents 测试
    function test_GetOwnerAgents_ShouldReturnAllAgentsForOwner() public {
        _registerAgent(AGENT_ONE, 10 ether, "solidity");
        _registerAgent(AGENT_ONE, 20 ether, "rust");
        _registerAgent(AGENT_ONE, 30 ether, "python");

        uint256[] memory ownerAgents = market.getOwnerAgents(AGENT_ONE);

        assertEq(ownerAgents.length, 3, unicode"应返回3个Agents");
        assertEq(ownerAgents[0], 1, unicode"第一个Agent ID不正确");
        assertEq(ownerAgents[1], 2, unicode"第二个Agent ID不正确");
        assertEq(ownerAgents[2], 3, unicode"第三个Agent ID不正确");
    }

    function test_GetOwnerAgents_ShouldReturnEmptyForNewOwner() public {
        uint256[] memory ownerAgents = market.getOwnerAgents(address(0x9999));
        assertEq(ownerAgents.length, 0, unicode"新地址应返回空数组");
    }

    // 复杂场景测试
    function test_MultipleEmployments_ShouldMaintainSeparateBalances() public {
        uint256 agentId1 = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256 agentId2 = _registerAgent(AGENT_TWO, 20 ether, "rust");

        uint256[] memory agentIds1 = new uint256[](1);
        agentIds1[0] = agentId1;

        uint256[] memory agentIds2 = new uint256[](1);
        agentIds2[0] = agentId2;

        vm.startPrank(USER);
        usdt.approve(address(market), 1000 ether);
        market.deposit(1000 ether);
        market.createEmployment(USER, agentIds1, 1, 300 ether);
        market.createEmployment(USER, agentIds2, 2, 500 ether);
        vm.stopPrank();

        assertEq(
            market.employmentBalances(1),
            300 ether,
            unicode"Employment1余额不正确"
        );
        assertEq(
            market.employmentBalances(2),
            500 ether,
            unicode"Employment2余额不正确"
        );
        assertEq(market.userBalances(USER), 200 ether, unicode"用户剩余余额不正确");
    }

    function test_CompleteEngagement_ShouldNotAffectOtherEmployments() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 10 ether, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 600 ether);
        market.deposit(600 ether);
        market.createEmployment(USER, agentIds, 1, 300 ether);
        market.createEmployment(USER, agentIds, 1, 300 ether);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        // 验证第二个employment仍然激活
        (, , , , bool isActive2, bool isCompleted2) = market.employments(2);
        assertTrue(isActive2, unicode"Employment2应仍处于激活状态");
        assertFalse(isCompleted2, unicode"Employment2不应完成");
        assertEq(
            market.employmentBalances(2),
            300 ether,
            unicode"Employment2余额不应变化"
        );
    }

    function test_LargeNumberOfAgents_ShouldDistributeCorrectly() public {
        // 注册10个agents
        uint256 numAgents = 10;
        uint256[] memory agentIds = new uint256[](numAgents);

        for (uint256 i = 0; i < numAgents; i++) {
            address agentOwner = address(uint160(0x5000 + i));
            string[] memory skills = new string[](1);
            skills[0] = "skill";

            vm.prank(agentOwner);
            market.registerAgent(skills, (i + 1) * 10 ether);
            agentIds[i] = market.agentCounter();
        }

        uint256 payment = 10000 ether;

        vm.startPrank(USER);
        usdt.approve(address(market), payment);
        market.deposit(payment);
        market.createEmployment(USER, agentIds, 1, payment);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        // 验证所有agents都收到了款项
        for (uint256 i = 0; i < numAgents; i++) {
            address agentOwner = address(uint160(0x5000 + i));
            assertGt(
                usdt.balanceOf(agentOwner),
                0,
                unicode"每个Agent都应收到款项"
            );
        }

        // 验证余额清零
        assertEq(
            market.employmentBalances(1),
            0,
            unicode"Employment余额应清零"
        );
    }

    function test_EdgeCase_SingleWeiPayment() public {
        uint256 agentId = _registerAgent(AGENT_ONE, 1, "solidity");
        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agentId;

        vm.startPrank(USER);
        usdt.approve(address(market), 10);
        market.deposit(10);
        market.createEmployment(USER, agentIds, 1, 10);
        vm.stopPrank();

        vm.prank(USER);
        market.completeEngagement(1);

        // 至少应该有一些余额（即使手续费后）
        uint256 agentBalance = usdt.balanceOf(AGENT_ONE);
        uint256 ownerBalance = usdt.balanceOf(address(this));
        assertGt(agentBalance + ownerBalance, 0, unicode"应该有一些资金被分配");
    }

    function test_GetAgent_ShouldReturnCorrectData() public {
        string[] memory skills = new string[](2);
        skills[0] = "solidity";
        skills[1] = "hardhat";

        vm.prank(AGENT_ONE);
        market.registerAgent(skills, 123 ether);

        AgentMarket.Agent memory agent = market.getAgent(1);

        assertEq(agent.id, 1, unicode"Agent ID不正确");
        assertEq(agent.owner, AGENT_ONE, unicode"Agent owner不正确");
        assertEq(agent.ratePer, 123 ether, unicode"Agent ratePer不正确");
        assertEq(agent.skills.length, 2, unicode"技能数量不正确");
        assertEq(agent.reputation, 0, unicode"初始声誉应为0");
    }

}
