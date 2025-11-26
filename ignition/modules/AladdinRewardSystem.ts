import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

/**
 * Aladdin Reward System 部署模块
 *
 * Hardhat 3.0 推荐的 Ignition 部署方式
 *
 * 使用方法:
 *   # 部署到本地网络
 *   npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts
 *
 *   # 部署到 Sepolia（使用预设的 USDT）
 *   npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts --network sepolia --parameters ignition/parameters/sepolia.json
 *
 *   # 部署到 localhost（创建测试 USDT）
 *   npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts --network localhost
 */

const REWARD_POOL_AMOUNT = 400_000_000n * 10n ** 18n; // 4 亿 ALD
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

export default buildModule("AladdinRewardSystem", (m) => {
  // 获取部署账户
  const deployer = m.getAccount(0);

  // 1. 部署测试 USDT（使用 AladdinToken 作为 mock）
  // 注意：即使在 Sepolia，也使用 mock 以便测试
  const usdt = m.contract("AladdinToken", [deployer], {
    id: "MockUSDT",
  });

  // 2. 部署 AladdinToken (10 亿供应量)
  const aladdinToken = m.contract("AladdinToken", [deployer], {
    id: "AladdinToken",
  });

  // 3. 部署 AgentMarket（初始 RewardManager 为 ZeroAddress）
  const agentMarket = m.contract("AgentMarket", [usdt, ZERO_ADDRESS], {
    id: "AgentMarket",
  });

  // 4. 部署 RewardManager
  const rewardManager = m.contract(
    "RewardManager",
    [aladdinToken, agentMarket],
    {
      id: "RewardManager",
    }
  );

  // 5. 设置 AgentMarket 的 RewardManager 地址
  m.call(agentMarket, "setRewardManager", [rewardManager], {
    id: "SetRewardManager",
  });

  // 6. 转移 4 亿 ALD 到 RewardManager 奖励池
  m.call(aladdinToken, "transfer", [rewardManager, REWARD_POOL_AMOUNT], {
    id: "FundRewardPool",
  });

  // 7. 部署 YieldProxy
  const yieldProxy = m.contract("YieldProxy", [usdt], {
    id: "YieldProxy",
  });

  // 注意：跳过 AaveYieldStrategy 部署
  // 需要有效的 Aave 协议地址才能部署，建议通过单独模块部署

  // 返回部署的合约实例
  return {
    aladdinToken,
    usdt,
    agentMarket,
    rewardManager,
    yieldProxy,
  };
});
