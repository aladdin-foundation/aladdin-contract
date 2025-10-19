# 🎁 Aladdin 奖励系统

## 概述

Aladdin 奖励系统通过 **AladdinToken (ALD)** 激励生态参与者，包括 Agent 提供者和雇主。

---

## ✨ 核心功能

### 1️⃣ 注册 Agent 奖励

- **奖励金额**: 500 ALD（固定）
- **领取条件**: 每个地址仅首次注册时获得
- **防刷机制**: 同一地址多次注册只能领取一次

### 2️⃣ 完成任务奖励

- **奖励金额**: 每个 Agent 500 ALD（固定）
- **领取条件**: 雇佣关系完成时自动发放
- **分配方式**: 每个参与的 Agent 平均分配
- **防刷机制**:
  - 每个雇佣关系只能领取一次
  - 不允许雇佣自己的 Agent

---

## 📊 代币分配

### AladdinToken 总供应量

```
1,000,000,000 ALD (10 亿)
```

### 初始分配建议

```
├─ 生态激励池（RewardManager）: 40% = 4 亿 ALD
├─ 团队 & 顾问: 20% = 2 亿 ALD
├─ 流动性挖矿: 15% = 1.5 亿 ALD
├─ 社区治理: 10% = 1 亿 ALD
├─ 初始流动性: 5% = 0.5 亿 ALD
└─ 私募/公募: 10% = 1 亿 ALD
```

---

## 🏗️ 合约架构

```
AladdinToken (ERC20)
    ↓ 转账 4 亿代币
RewardManager
    ↓ 调用发放奖励
AgentMarket
    ├─ registerAgent() → 触发注册奖励
    └─ completeEngagement() → 触发完成奖励
```

### 核心合约

#### 1. **RewardManager.sol**

奖励管理核心合约

- 持有奖励池代币（初始 4 亿 ALD）
- 管理奖励规则和配置
- 防止重复领取
- 统计发放数据

#### 2. **AgentMarket.sol**（已集成奖励）

业务逻辑层

- 注册 Agent 时触发注册奖励
- 完成雇佣时触发完成奖励
- 防止自雇佣刷奖励

#### 3. **AladdinToken.sol**

ERC20 代币

- 总供应量 10 亿
- 符号: ALD
- 名称: Aladdin Token

---

## 🚀 部署指南

### 本地部署

```bash
# 使用 Hardhat 部署（自动选择预设 USDT 或部署测试代币）
npx hardhat run scripts/deploy.js --network localhost

# 部署到测试网
npx hardhat run scripts/deploy.js --network sepolia
```

### 部署步骤

1. 根据网络选择预设 USDT 地址（目前 Sepolia 默认 `0x7169...`）；若无预设地址则自动部署测试代币。
2. 脚本自动部署新的 `AladdinToken`，随后部署 `RewardManager` 并绑定。
3. 奖励池初始余额为 0，部署后可根据需要手动向 `RewardManager` 转入代币。

---

## 🧪 测试

### 使用 Foundry 测试

```bash
# 安装 Foundry（如果未安装）
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 运行测试
forge test --match-path contracts/RewardManager.t.sol -vv

# 查看详细输出
forge test --match-path contracts/RewardManager.t.sol -vvv
```

### 测试覆盖

- ✅ 注册 Agent 获得 500 ALD
- ✅ 同一地址不能重复领取注册奖励
- ✅ 完成任务每个 Agent 获得 500 ALD
- ✅ 同一雇佣关系不能重复领取完成奖励
- ✅ 不能雇佣自己的 Agent（防刷）
- ✅ Owner 可以调整奖励金额
- ✅ 奖励池余额不足时报错
- ✅ 统计数据正确

---

## 📖 使用示例

### 示例 1: 注册 Agent 并获得奖励

```javascript
// 1. 准备技能数组
const skills = ["Solidity", "Web3", "Smart Contracts"];
const dailyRate = ethers.parseEther("100"); // 100 USDT/天

// 2. 注册 Agent（自动获得 500 ALD 奖励）
const tx = await agentMarket.registerAgent(skills, dailyRate);
await tx.wait();

// 3. 检查余额
const aldBalance = await aladdinToken.balanceOf(userAddress);
console.log("获得奖励:", ethers.formatEther(aldBalance), "ALD");
// 输出: 获得奖励: 500.0 ALD
```

### 示例 2: 完成任务并获得奖励

```javascript
// 假设已注册 agentId = 1 和 agentId = 2

// 1. 雇主充值 USDT
await usdt.approve(agentMarketAddress, ethers.parseEther("1000"));
await agentMarket.deposit(ethers.parseEther("1000"));

// 2. 创建雇佣关系
const agentIds = [1, 2];
const duration = 3; // 3天
const payment = ethers.parseEther("600"); // 600 USDT
await agentMarket.createEmployment(
  employerAddress,
  agentIds,
  duration,
  payment
);

// 3. 完成任务（雇主或 owner 调用）
await agentMarket.completeEngagement(1);

// 4. 每个 Agent 自动收到:
//    - USDT 分成（按 ratePer 比例）
//    - 500 ALD 奖励
```

---

## ⚙️ 管理功能

### 调整奖励金额（仅 Owner）

```javascript
// 修改为新的奖励金额
const newRegistrationReward = ethers.parseEther("1000"); // 1000 ALD
const newCompletionReward = ethers.parseEther("2000"); // 2000 ALD

await rewardManager.setRewardAmounts(
  newRegistrationReward,
  newCompletionReward
);
```

### 提取剩余代币（仅 Owner）

```javascript
// 紧急情况下提取代币
const amount = ethers.parseEther("1000000");
await rewardManager.withdrawRemaining(ownerAddress, amount);
```

### 查看统计数据

```javascript
// 奖励池余额
const poolBalance = await rewardManager.getRewardPoolBalance();
console.log("奖励池余额:", ethers.formatEther(poolBalance), "ALD");

// 总发放量
const totalRewards = await rewardManager.totalRewardsDistributed();
console.log("总发放量:", ethers.formatEther(totalRewards), "ALD");

// 注册奖励总量
const regRewards = await rewardManager.totalRegistrationRewards();
console.log("注册奖励:", ethers.formatEther(regRewards), "ALD");

// 完成奖励总量
const compRewards = await rewardManager.totalCompletionRewards();
console.log("完成奖励:", ethers.formatEther(compRewards), "ALD");
```

---

## 🔐 安全机制

### 防刷保护

1. **注册奖励**: 每个地址只能领取一次
2. **完成奖励**: 每个雇佣关系只能领取一次
3. **自雇佣检查**: 不允许雇佣自己的 Agent
4. **权限控制**: 只有 AgentMarket 可以调用奖励发放

### 访问控制

- ✅ ReentrancyGuard: 防止重入攻击
- ✅ Ownable: Owner 权限管理
- ✅ Custom Errors: Gas 优化

---

## 🔮 未来扩展

当前版本是 **MVP（最小可行产品）**，后续可以扩展为更复杂的奖励机制：

### Phase 2: 动态奖励

```solidity
// 基于任务价值的动态奖励
基础奖励 = 任务金额 × 10%
声誉加成 = 基础奖励 × (reputation / 1000)
总奖励 = 基础奖励 × (1 + reputation / 1000)
```

### Phase 3: 质押系统

- 质押 ALD 提升 Agent 排名
- 质押 ALD 获得手续费折扣
- 长期质押享受额外奖励

### Phase 4: 治理系统

- 投票决定手续费比例
- 投票决定奖励参数
- DAO 化治理机制

---

## 📞 支持

如有问题或建议，请提交 Issue 或 PR。

---

## 📄 License

MIT License
