# 🚀 Hardhat 3.0 部署指南

## 📖 Hardhat 3.0 的两种部署方式

Hardhat 3.0 提供了两种部署智能合约的方式：

### 1️⃣ **Hardhat Ignition**（官方推荐 ⭐）

**优点：**
- ✅ 声明式部署，代码更清晰
- ✅ 自动管理部署状态（可恢复、可重放）
- ✅ 内置验证和回滚机制
- ✅ 支持复杂的部署流程
- ✅ 更安全可靠

**缺点：**
- ❌ 学习曲线稍高
- ❌ 某些动态逻辑不太方便

**适用场景：**
- 生产环境部署
- 需要可重复部署
- 团队协作项目

---

### 2️⃣ **传统脚本方式**

**优点：**
- ✅ 更灵活
- ✅ 适合复杂逻辑
- ✅ 容易理解

**缺点：**
- ❌ 需要手动管理状态
- ❌ 容易出错
- ❌ 不支持自动恢复

**适用场景：**
- 快速测试
- 一次性部署
- 需要复杂条件判断

---

## 🎯 方式 1: Hardhat Ignition（推荐）

### 文件结构

```
ignition/
├── modules/
│   └── AladdinRewardSystem.ts    # 部署模块
└── parameters/
    └── sepolia.json               # Sepolia 网络参数
```

### 部署命令

#### **本地测试网**
```bash
# 1. 启动本地节点
npx hardhat node

# 2. 新终端部署
npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts --network localhost
```

#### **Sepolia 测试网**
```bash
# 使用预设的 USDT 地址
npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia.json
```

### 部署输出示例

```bash
✔ Confirm deploy to network sepolia (11155111)? … yes

Hardhat Ignition 🚀

Deploying [ AladdinRewardSystem ]

Batch #1
  Executed AladdinRewardSystem#AladdinToken
  Executed AladdinRewardSystem#AgentMarket
  Executed AladdinRewardSystem#RewardManager

Batch #2
  Executed AladdinRewardSystem#SetRewardManager
  Executed AladdinRewardSystem#FundRewardPool

[ AladdinRewardSystem ] successfully deployed 🚀

Deployed Addresses

AladdinRewardSystem#AladdinToken - 0xABCD...
AladdinRewardSystem#AgentMarket - 0x1234...
AladdinRewardSystem#RewardManager - 0x5678...
```

### 验证合约

```bash
# 自动验证所有合约
npx hardhat ignition verify chain-11155111
```

---

## 🛠️ 方式 2: 传统脚本（当前使用）

### 文件

```
scripts/
└── deploy.js    # 部署脚本
```

### 部署命令

```bash
# 本地测试网
npx hardhat run scripts/deploy.js --network localhost

# Sepolia 测试网
npx hardhat run scripts/deploy.js --network sepolia
```

### 改进内容

✅ 已更新 `scripts/deploy.js`，现在包含：
- 自动转账 4 亿 ALD 到奖励池
- 验证奖励池余额
- 格式化的输出
- 完整的验证命令

### 部署输出示例

```bash
部署账户: 0x1234...
使用预设 sepolia USDT 地址: 0x7169...
AgentMarket 部署成功: 0xABCD...
AladdinToken (Reward) 已部署: 0xEF01...
RewardManager 部署成功: 0x5678...
AgentMarket 已成功绑定 RewardManager。

正在转移 4 亿 ALD 到奖励池...
✅ 奖励池已注资 4 亿 ALD
奖励池余额: 400000000.0 ALD

============================================================
🎉 部署完成！关键地址：
============================================================
USDT Token:      0x7169...
AladdinToken:    0xEF01...
AgentMarket:     0xABCD...
RewardManager:   0x5678...
============================================================

📝 验证命令（Sepolia）：
npx hardhat verify --network sepolia 0xEF01... "0x1234..."
npx hardhat verify --network sepolia 0xABCD... "0x7169..." "0x5678..."
npx hardhat verify --network sepolia 0x5678... "0xEF01..." "0xABCD..."
```

---

## 📊 两种方式对比

| 特性 | Hardhat Ignition | 传统脚本 |
|------|----------------|---------|
| **易用性** | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| **可靠性** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| **状态管理** | ✅ 自动 | ❌ 手动 |
| **可恢复** | ✅ 支持 | ❌ 不支持 |
| **灵活性** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **适合场景** | 生产环境 | 快速测试 |

---

## 🚀 快速部署

### 方式 1: Hardhat Ignition

```bash
# 1. 编译
npm run compile

# 2. 部署到 Sepolia
npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia.json

# 3. 验证
npx hardhat ignition verify chain-11155111
```

### 方式 2: 传统脚本

```bash
# 1. 编译
npm run compile

# 2. 部署到 Sepolia
npx hardhat run scripts/deploy.js --network sepolia

# 3. 验证（复制输出的命令）
npx hardhat verify --network sepolia <ADDRESS> <ARGS>
```

---

## 💡 最佳实践

### 何时使用 Ignition

✅ **推荐：**
- 主网部署
- 需要审计的项目
- 团队协作
- 需要可重复部署

❌ **不推荐：**
- 快速测试
- 简单脚本
- 学习阶段

### 何时使用传统脚本

✅ **推荐：**
- 本地开发
- 复杂逻辑
- 临时脚本

❌ **不推荐：**
- 生产环境
- 需要状态管理

---

## 🔧 部署后操作

### 测试部署的合约

```bash
npx hardhat console --network sepolia

// 连接合约
const market = await ethers.getContractAt("AgentMarket", "0x...")
const ald = await ethers.getContractAt("AladdinToken", "0x...")
const reward = await ethers.getContractAt("RewardManager", "0x...")

// 检查配置
console.log("手续费:", await market.feePercentage())  // 200
console.log("奖励池:", ethers.formatEther(await reward.getRewardPoolBalance()))  // 400000000.0

// 测试注册 Agent
const tx = await market.registerAgent(["Solidity"], ethers.parseEther("100"))
await tx.wait()

// 检查奖励
const [signer] = await ethers.getSigners()
console.log("ALD 余额:", ethers.formatEther(await ald.balanceOf(signer.address)))
// 应该是 500.0
```

---

## 🐛 常见问题

### Q1: Ignition 部署中断了怎么办？

重新运行相同命令，Ignition 会自动继续：
```bash
npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts --network sepolia
```

### Q2: 如何重新部署？

**Ignition：**
```bash
rm -rf ignition/deployments/chain-11155111
npx hardhat ignition deploy ...
```

**传统脚本：**
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

### Q3: 如何查看已部署地址？

**Ignition：**
```bash
cat ignition/deployments/chain-11155111/deployed_addresses.json
```

**传统脚本：**
从控制台输出复制

---

## 📝 总结

### 推荐使用方案

| 场景 | 推荐方式 |
|------|---------|
| **首次学习** | 传统脚本 `scripts/deploy.js` |
| **测试网部署** | 传统脚本（更快） |
| **主网部署** | Hardhat Ignition（更安全） |
| **生产环境** | Hardhat Ignition（可审计） |

### 快速命令参考

```bash
# 传统脚本部署（推荐用于测试）
npx hardhat run scripts/deploy.js --network sepolia

# Ignition 部署（推荐用于生产）
npx hardhat ignition deploy ignition/modules/AladdinRewardSystem.ts \
  --network sepolia \
  --parameters ignition/parameters/sepolia.json

# 验证合约
npx hardhat verify --network sepolia <ADDRESS> <ARGS>
```

---

## 📚 更多资源

- [Hardhat Ignition 文档](https://hardhat.org/ignition)
- [Hardhat 部署文档](https://hardhat.org/docs/learn-more/deploying-contracts)
- [本项目部署指南](DEPLOYMENT_GUIDE.md)
