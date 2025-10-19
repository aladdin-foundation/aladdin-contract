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
  const aTokenAddress = m.getParameter("aTokenAddress", ZERO_ADDRESS);
  const lendingPoolAddress = m.getParameter(
    "lendingPoolAddress",
    ZERO_ADDRESS
  );

  // 1. 部署或使用现有 USDT
  let usdt;
  if (usdtAddress === ZERO_ADDRESS) {
    // 部署测试 USDT
    usdt = m.contract("AladdinToken", [deployer], {
      id: "MockUSDT",
    });
  } else {
    // 使用现有 USDT 地址
    usdt = m.contractAt("AladdinToken", usdtAddress, {
      id: "USDT",
    });
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

  // 7. 部署 YieldProxy
  const yieldProxy = m.contract("YieldProxy", [usdt], {
    id: "YieldProxy",
  });

  let aaveYieldStrategy;
  const shouldDeployAaveStrategy =
    aTokenAddress !== ZERO_ADDRESS && lendingPoolAddress !== ZERO_ADDRESS;

  if (shouldDeployAaveStrategy) {
    aaveYieldStrategy = m.contract(
      "AaveYieldStrategy",
      [usdt, aTokenAddress, lendingPoolAddress],
      {
        id: "AaveYieldStrategy",
      }
    );

    m.call(yieldProxy, "authorizeStrategy", [aaveYieldStrategy], {
      id: "AuthorizeAaveStrategy",
    });

    m.call(yieldProxy, "switchStrategy", [aaveYieldStrategy], {
      id: "SwitchToAaveStrategy",
    });
  }

  // 返回部署的合约实例
  return {
    aladdinToken,
    usdt,
    agentMarket,
    rewardManager,
    yieldProxy,
    aaveYieldStrategy,
  };
});
