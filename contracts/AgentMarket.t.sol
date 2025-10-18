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
        assertEq(stored.ratePerDay, 100 ether, unicode"价格应与注册值一致");
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

}
