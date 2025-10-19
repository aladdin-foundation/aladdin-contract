// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./RewardManager.sol";
import "./AladdinToken.sol";
import "./AgentMarket.sol";

contract RewardManagerTest is Test {
    RewardManager public rewardManager;
    AladdinToken public aladdinToken;
    AgentMarket public agentMarket;
    AladdinToken public usdt;

    address public owner;
    address public agent1;
    address public agent2;
    address public employer;

    uint256 constant INITIAL_REWARD_POOL = 400_000_000 * 10**18; // 4亿代币

    function setUp() public {
        owner = address(this);
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        employer = makeAddr("employer");

        // 部署 AladdinToken（10亿供应量）
        aladdinToken = new AladdinToken(owner);

        // 部署 USDT 测试代币
        usdt = new AladdinToken(owner);

        // 部署 AgentMarket（先用临时地址）
        agentMarket = new AgentMarket(address(usdt), address(0));

        // 部署 RewardManager
        rewardManager = new RewardManager(address(aladdinToken), address(agentMarket));

        // 更新 AgentMarket 的 RewardManager 地址
        agentMarket.setRewardManager(address(rewardManager));

        // 转移 4 亿代币到 RewardManager 作为奖励池
        aladdinToken.transfer(address(rewardManager), INITIAL_REWARD_POOL);

        // 给 employer 分配 USDT 用于测试
        usdt.transfer(employer, 10000 * 10**18);

        // 给 agent1 和 agent2 gas 费
        vm.deal(agent1, 1 ether);
        vm.deal(agent2, 1 ether);
    }

    /// 测试注册 Agent 获得奖励
    function test_RegistrationReward() public {
        string[] memory skills = new string[](2);
        skills[0] = "Solidity";
        skills[1] = "Web3";

        // agent1 注册 Agent
        vm.startPrank(agent1);
        agentMarket.registerAgent(skills, 100 * 10**18);
        vm.stopPrank();

        // 验证 agent1 收到 500 ALD
        assertEq(aladdinToken.balanceOf(agent1), 500 * 10**18, unicode"注册奖励应为 500 ALD");

        // 验证统计数据
        assertEq(
            rewardManager.totalRegistrationRewards(),
            500 * 10**18,
            unicode"注册奖励统计应为 500 ALD"
        );
    }

    /// 测试同一地址只能领取一次注册奖励
    function test_CannotClaimRegistrationRewardTwice() public {
        string[] memory skills = new string[](1);
        skills[0] = "AI";

        // agent1 注册第一个 Agent
        vm.startPrank(agent1);
        agentMarket.registerAgent(skills, 100 * 10**18);

        // 检查余额
        uint256 balanceAfterFirst = aladdinToken.balanceOf(agent1);
        assertEq(balanceAfterFirst, 500 * 10**18, unicode"首次注册应获得 500 ALD");

        // 注册第二个 Agent（应该失败）
        vm.expectRevert(RewardManager.AlreadyClaimed.selector);
        agentMarket.registerAgent(skills, 200 * 10**18);

        vm.stopPrank();
    }

    /// 测试完成任务获得奖励
    function test_CompletionReward() public {
        // 1. 注册两个 Agent
        string[] memory skills = new string[](1);
        skills[0] = "Development";

        vm.prank(agent1);
        agentMarket.registerAgent(skills, 100 * 10**18); // agentId = 1

        vm.prank(agent2);
        agentMarket.registerAgent(skills, 150 * 10**18); // agentId = 2

        // 2. employer 充值 USDT
        vm.startPrank(employer);
        usdt.approve(address(agentMarket), 10000 * 10**18);
        agentMarket.deposit(1000 * 10**18);

        // 3. 创建雇佣关系（雇佣两个 Agent，1天）
        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = 1;
        agentIds[1] = 2;

        uint256 payment = 300 * 10**18; // 支付 300 USDT
        agentMarket.createEmployment(employer, agentIds, 1, payment);

        // 4. 完成任务
        uint256 agent1BalanceBefore = aladdinToken.balanceOf(agent1);
        uint256 agent2BalanceBefore = aladdinToken.balanceOf(agent2);

        agentMarket.completeEngagement(1);
        vm.stopPrank();

        // 5. 验证每个 Agent 收到 500 ALD 奖励（注册 500 + 完成 500 = 1000）
        assertEq(
            aladdinToken.balanceOf(agent1),
            agent1BalanceBefore + 500 * 10**18,
            unicode"agent1 应获得 500 ALD 完成奖励"
        );
        assertEq(
            aladdinToken.balanceOf(agent2),
            agent2BalanceBefore + 500 * 10**18,
            unicode"agent2 应获得 500 ALD 完成奖励"
        );

        // 6. 验证统计数据
        assertEq(
            rewardManager.totalCompletionRewards(),
            1000 * 10**18,
            unicode"完成奖励统计应为 1000 ALD"
        );
    }

    /// 测试不能重复领取完成奖励
    function test_CannotClaimCompletionRewardTwice() public {
        // 1. 注册 Agent
        string[] memory skills = new string[](1);
        skills[0] = "Testing";

        vm.prank(agent1);
        agentMarket.registerAgent(skills, 100 * 10**18);

        // 2. 创建并完成雇佣
        vm.startPrank(employer);
        usdt.approve(address(agentMarket), 10000 * 10**18);
        agentMarket.deposit(500 * 10**18);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = 1;

        agentMarket.createEmployment(employer, agentIds, 1, 150 * 10**18);
        agentMarket.completeEngagement(1);

        // 3. 尝试再次完成（应该失败）
        // 注意：completeEngagement 先检查 isActive，所以会先触发 NotActive 错误
        vm.expectRevert(AgentMarket.NotActive.selector);
        agentMarket.completeEngagement(1);

        vm.stopPrank();
    }

    /// 测试只有 AgentMarket 可以调用完成奖励发放
    function test_CompletionReward_ShouldRevertWhenCallerNotAgentMarket() public {
        address[] memory agentOwners = new address[](1);
        agentOwners[0] = agent1;

        vm.expectRevert(RewardManager.OnlyAgentMarket.selector);
        rewardManager.claimCompletionReward(10, agentOwners);
    }

    /// 测试完成奖励只能领取一次
    function test_CompletionReward_ShouldRevertWhenEmploymentAlreadyClaimed() public {
        address[] memory agentOwners = new address[](2);
        agentOwners[0] = agent1;
        agentOwners[1] = agent2;

        vm.prank(address(agentMarket));
        rewardManager.claimCompletionReward(77, agentOwners);

        assertTrue(
            rewardManager.hasClaimedEmployment(77),
            unicode"雇佣记录应标记为已领取"
        );
        assertEq(
            rewardManager.totalCompletionRewards(),
            rewardManager.completionReward() * 2,
            unicode"完成奖励统计应累加两次"
        );

        vm.expectRevert(RewardManager.AlreadyClaimed.selector);
        vm.prank(address(agentMarket));
        rewardManager.claimCompletionReward(77, agentOwners);
    }

    /// 测试奖励池余额不足时领取完成奖励会失败
    function test_CompletionReward_ShouldRevertWhenPoolInsufficient() public {
        // 先提取走绝大部分奖励代币，只保留不足以支付一次奖励的余额
        uint256 balance = aladdinToken.balanceOf(address(rewardManager));
        rewardManager.withdrawRemaining(owner, balance - 100);

        address[] memory agentOwners = new address[](1);
        agentOwners[0] = agent1;

        vm.expectRevert(RewardManager.InsufficientRewardBalance.selector);
        vm.prank(address(agentMarket));
        rewardManager.claimCompletionReward(88, agentOwners);
    }

    /// 测试多名 Agent 领取完成奖励时统计数据和余额更新正确
    function test_CompletionReward_ShouldUpdateTotalsForMultipleAgents() public {
        address[] memory agentOwners = new address[](2);
        agentOwners[0] = agent1;
        agentOwners[1] = agent2;

        uint256 agent1BalanceBefore = aladdinToken.balanceOf(agent1);
        uint256 agent2BalanceBefore = aladdinToken.balanceOf(agent2);

        vm.prank(address(agentMarket));
        rewardManager.claimCompletionReward(99, agentOwners);

        uint256 rewardPerAgent = rewardManager.completionReward();
        assertEq(
            aladdinToken.balanceOf(agent1),
            agent1BalanceBefore + rewardPerAgent,
            unicode"Agent1 完成奖励金额异常"
        );
        assertEq(
            aladdinToken.balanceOf(agent2),
            agent2BalanceBefore + rewardPerAgent,
            unicode"Agent2 完成奖励金额异常"
        );

        uint256 expectedTotal = rewardPerAgent * agentOwners.length;
        assertEq(
            rewardManager.totalCompletionRewards(),
            expectedTotal,
            unicode"完成奖励统计应等于两名 Agent 的总和"
        );
        assertEq(
            rewardManager.totalRewardsDistributed(),
            expectedTotal,
            unicode"总奖励发放应与完成奖励保持一致"
        );
        assertTrue(
            rewardManager.hasClaimedEmployment(99),
            unicode"雇佣记录应被标记为已领取"
        );
    }

    /// 测试防止自雇佣
    function test_CannotHireOwnAgent() public {
        // 1. employer 注册 Agent
        string[] memory skills = new string[](1);
        skills[0] = "SelfHire";

        vm.prank(employer);
        agentMarket.registerAgent(skills, 100 * 10**18); // agentId = 1

        // 2. employer 尝试雇佣自己的 Agent
        vm.startPrank(employer);
        usdt.approve(address(agentMarket), 10000 * 10**18);
        agentMarket.deposit(500 * 10**18);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = 1;

        vm.expectRevert(AgentMarket.CannotHireOwnAgent.selector);
        agentMarket.createEmployment(employer, agentIds, 1, 150 * 10**18);

        vm.stopPrank();
    }

    /// 测试 owner 可以调整奖励金额
    function test_OwnerCanUpdateRewardAmounts() public {
        uint256 newRegistrationReward = 1000 * 10**18;
        uint256 newCompletionReward = 2000 * 10**18;

        rewardManager.setRewardAmounts(newRegistrationReward, newCompletionReward);

        assertEq(
            rewardManager.registrationReward(),
            newRegistrationReward,
            unicode"注册奖励应已更新"
        );
        assertEq(
            rewardManager.completionReward(),
            newCompletionReward,
            unicode"完成奖励应已更新"
        );
    }

    /// 测试非 owner 不能调整奖励金额
    function test_NonOwnerCannotUpdateRewardAmounts() public {
        vm.prank(agent1);
        vm.expectRevert();
        rewardManager.setRewardAmounts(1000 * 10**18, 2000 * 10**18);
    }

    /// 测试奖励池余额不足时报错
    function test_RevertWhenInsufficientRewardBalance() public {
        // 1. 提取几乎所有代币
        uint256 balance = aladdinToken.balanceOf(address(rewardManager));
        rewardManager.withdrawRemaining(owner, balance - 100 * 10**18);

        // 2. 尝试注册（奖励池余额不足 500 ALD）
        string[] memory skills = new string[](1);
        skills[0] = "Test";

        vm.prank(agent1);
        vm.expectRevert(RewardManager.InsufficientRewardBalance.selector);
        agentMarket.registerAgent(skills, 100 * 10**18);
    }

    /// 测试获取奖励池余额
    function test_GetRewardPoolBalance() public {
        uint256 balance = rewardManager.getRewardPoolBalance();
        assertEq(balance, INITIAL_REWARD_POOL, unicode"奖励池余额应为 4 亿 ALD");
    }

    /// 测试总奖励发放统计
    function test_TotalRewardsDistributed() public {
        // 注册一个 Agent
        string[] memory skills = new string[](1);
        skills[0] = "Stats";

        vm.prank(agent1);
        agentMarket.registerAgent(skills, 100 * 10**18);

        // 创建并完成雇佣
        vm.startPrank(employer);
        usdt.approve(address(agentMarket), 10000 * 10**18);
        agentMarket.deposit(500 * 10**18);

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = 1;

        agentMarket.createEmployment(employer, agentIds, 1, 150 * 10**18);
        agentMarket.completeEngagement(1);
        vm.stopPrank();

        // 验证总发放量 = 注册奖励 + 完成奖励
        assertEq(
            rewardManager.totalRewardsDistributed(),
            1000 * 10**18, // 500 + 500
            unicode"总发放量应为 1000 ALD"
        );
    }
}
