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

    function test_RegisterAgent_ShouldPersistMetadata() public {
        _registerAgent(AGENT_ONE, 100 ether, "solidity");

        AgentMarket.Agent memory stored = market.getAgent(AGENT_ONE);
        assertEq(stored.agentAddress, AGENT_ONE, unicode"Agent地址应被记录");
        assertEq(stored.ratePerDay, 100 ether, unicode"价格应与注册值一致");
        assertEq(stored.skills.length, 1, unicode"技能列表长度异常");
        assertEq(
            keccak256(bytes(stored.skills[0])),
            keccak256(bytes("solidity")),
            unicode"技能名称不匹配"
        );
    }

    function test_RegisterAgent_RevertWhenDuplicate() public {
        _registerAgent(AGENT_ONE, 1 ether, "ai");

        string[] memory skills = new string[](1);
        skills[0] = "ai";
        vm.prank(AGENT_ONE);
        vm.expectRevert(AgentMarket.AlreadyRegistered.selector);
        market.registerAgent(skills, 1 ether);
    }

    function test_CreateEmployment_RevertWhenAgentNotRegistered() public {
        address[] memory agentsList = new address[](1);
        agentsList[0] = AGENT_ONE;

        vm.expectRevert(AgentMarket.AgentNotRegistered.selector);
        market.createEmployment(agentsList, 1, 100 ether);
    }

    function test_CreateEmployment_ShouldLockFunds() public {
        _registerAgent(AGENT_ONE, 25 ether, "zk");

        address[] memory agentsList = new address[](1);
        agentsList[0] = AGENT_ONE;

        vm.startPrank(USER);
        usdt.approve(address(market), 500 ether);
        market.createEmployment(agentsList, 2, 500 ether);
        vm.stopPrank();

        assertEq(market.employmentCounter(), 1, unicode"计数器未更新");
        assertEq(market.employmentBalances(1), 500 ether, unicode"托管金额不正确");
        assertEq(usdt.balanceOf(address(market)), 500 ether, unicode"合约持有金额异常");

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
        _registerAgent(AGENT_ONE, 100 ether, "ml");
        address[] memory agentsList = new address[](1);
        agentsList[0] = AGENT_ONE;

        vm.startPrank(USER);
        usdt.approve(address(market), 50 ether);
        vm.expectRevert(AgentMarket.PaymentTooLow.selector);
        market.createEmployment(agentsList, 1, 50 ether);
        vm.stopPrank();
    }

    function test_CompleteEngagement_ShouldPayAgentsAndOwner() public {
        _registerAgent(AGENT_ONE, 10 ether, "solidity");
        _registerAgent(AGENT_TWO, 30 ether, "design");

        address[] memory agentsList = new address[](2);
        agentsList[0] = AGENT_ONE;
        agentsList[1] = AGENT_TWO;

        vm.startPrank(USER);
        usdt.approve(address(market), 1_000 ether);
        market.createEmployment(agentsList, 2, 1_000 ether);
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
        _registerAgent(AGENT_ONE, 5 ether, "solidity");

        address[] memory agentsList = new address[](1);
        agentsList[0] = AGENT_ONE;

        vm.startPrank(USER);
        usdt.approve(address(market), 200 ether);
        market.createEmployment(agentsList, 1, 200 ether);
        vm.stopPrank();

        vm.expectRevert(AgentMarket.NoPermission.selector);
        vm.prank(address(0xdead));
        market.completeEngagement(1);
    }

    function _registerAgent(
        address agent,
        uint256 rate,
        string memory skill
    ) internal {
        string[] memory skills = new string[](1);
        skills[0] = skill;
        vm.prank(agent);
        market.registerAgent(skills, rate);
    }
}
