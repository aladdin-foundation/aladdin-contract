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

  // 参数：USDT 地址（可通过 --parameters 覆盖）
  const usdtAddress = m.getParameter("usdtAddress", ZERO_ADDRESS);

  // 1. 部署或使用现有 USDT
  let usdt;
  if (usdtAddress === ZERO_ADDRESS) {
    // 部署测试 USDT
    usdt = m.contract("AladdinToken", [deployer], {
      id: "MockUSDT",
    });
    console.log("部署测试 USDT 代币");
  } else {
    // 使用现有 USDT 地址
    usdt = m.contractAt("AladdinToken", usdtAddress, {
      id: "USDT",
    });
    console.log("使用现有 USDT:", usdtAddress);
  }

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

  // 返回部署的合约实例
  return {
    aladdinToken,
    usdt,
    agentMarket,
    rewardManager,
  };
});
