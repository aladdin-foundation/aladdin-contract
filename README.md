# 🧞 Aladdin Contract - AI Agent 去中心化市场

> 一个基于以太坊的 AI Agent 雇佣市场，集成代币激励系统，实现 Agent 注册、雇佣关系管理、USDT 支付托管和 ALD 代币奖励。

[![Solidity](https://img.shields.io/badge/Solidity-0.8.20-blue)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-3.0.6-yellow)](https://hardhat.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-46%20passing-brightgreen)](#测试)

---

## 📖 目录

- [项目概述](#项目概述)
- [核心功能](#核心功能)
- [合约架构](#合约架构)
- [代币经济](#代币经济)
- [快速开始](#快速开始)
- [测试](#测试)
- [部署](#部署)
- [使用示例](#使用示例)
- [项目文档](#项目文档)
- [技术栈](#技术栈)
- [安全机制](#安全机制)
- [路线图](#路线图)

---

## 🎯 项目概述

Aladdin Contract 是一个去中心化的 AI Agent 雇佣市场，允许：

- 🤖 **Agent 提供者**注册 Agent 并设置日费率
- 💼 **雇主**通过托管 USDT 雇佣一个或多个 Agent
- 💰 **智能合约**管理资金托管、分配和手续费
- 🎁 **AladdinToken (ALD)** 激励生态参与者

### 核心价值

```
传统模式                        Aladdin 模式
中心化平台 → 抽取高额佣金      去中心化合约 → 2% 手续费
法币结算 → 跨境困难             USDT 结算 → 全球畅通
无激励机制                      ALD 代币激励 → 促进生态增长
```

---

## ✨ 核心功能

### 1️⃣ Agent 管理

- **注册 Agent**: 提供者可注册 Agent，设置技能标签和日费率
- **多 Agent 支持**: 每个地址可注册多个 Agent
- **技能标签**: 灵活的技能分类系统
- **声誉系统**: 记录 Agent 完成任务数和质量（预留扩展）

### 2️⃣ 雇佣系统

- **多 Agent 雇佣**: 一次雇佣最多 20 个 Agent
- **灵活定价**: 基于 Agent 日费率和雇佣天数
- **USDT 托管**: 雇主充值 USDT 到合约，创建雇佣时锁定资金
- **自动分配**: 完成时按 Agent 费率和时长比例分配报酬

### 3️⃣ 奖励机制 🎁

**AladdinToken (ALD) 激励生态参与：**

| 场景           | 奖励            | 说明                          |
| -------------- | --------------- | ----------------------------- |
| **注册 Agent** | 500 ALD         | 每个地址首次注册时发放        |
| **完成任务**   | 500 ALD / Agent | 雇佣关系完成时每个 Agent 获得 |

**防刷机制：**

- ✅ 注册奖励每地址仅一次
- ✅ 完成奖励每雇佣关系仅一次
- ✅ 禁止雇佣自己的 Agent

### 4️⃣ 支付与结算

- **USDT 结算**: 所有交易使用 USDT（稳定价值锚点）
- **2% 平台手续费**: 从雇佣支付中扣除
- **按比例分配**: 根据每个 Agent 的 `ratePer × duration` 权重分配
- **精确计算**: 处理除法余数，确保无资金损失

---

## 🏗️ 合约架构

```
┌─────────────────────────────────────────────────────────┐
│                    Aladdin Ecosystem                     │
└─────────────────────────────────────────────────────────┘
            │                   │                   │
            ▼                   ▼                   ▼
    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
    │ AladdinToken │    │ AgentMarket  │    │RewardManager │
    │   (ERC20)    │◄───│  (核心逻辑)  │◄───│  (奖励池)    │
    └──────────────┘    └──────────────┘    └──────────────┘
         10 亿供应             ▲                   4 亿 ALD
                              │
                    ┌─────────┴─────────┐
                    │                   │
                 雇主 USDT           Agent 提供者
                    │                   │
                    └─────────┬─────────┘
                              ▼
                      雇佣关系 & 奖励
```

### 核心合约

#### 1. **AladdinToken.sol**

ERC20 代币合约

- **总供应量**: 1,000,000,000 ALD (10 亿)
- **符号**: ALD
- **名称**: Aladdin Token
- **功能**: 生态激励、治理（预留）、质押（预留）

#### 2. **AgentMarket.sol**

市场核心业务逻辑

- Agent 注册与管理
- 雇佣关系创建与管理
- USDT 托管与分配
- 集成 RewardManager 自动发放 ALD 奖励
- 2% 手续费收取

#### 3. **RewardManager.sol**

奖励管理合约

- 持有 4 亿 ALD 奖励池
- 管理注册奖励和完成奖励
- 防重复领取机制
- 统计发放数据
- Owner 可调整奖励参数

---

## 💰 代币经济

### AladdinToken 分配方案（10 亿总供应）

```
├─ 生态激励池（RewardManager）: 40% = 4 亿 ALD
│  ├─ 注册奖励
│  ├─ 完成任务奖励
│  └─ 未来扩展激励
│
├─ 团队 & 顾问: 20% = 2 亿 ALD
│  └─ 4 年线性解锁
│
├─ 流动性挖矿: 15% = 1.5 亿 ALD
│  └─ 质押奖励（Phase 2）
│
├─ 社区治理（DAO 金库）: 10% = 1 亿 ALD
│
├─ 初始流动性: 5% = 0.5 亿 ALD
│
└─ 私募/公募: 10% = 1 亿 ALD
   └─ 6 个月锁定期
```

### 代币功能

| 功能         | 当前状态   | 未来扩展                 |
| ------------ | ---------- | ------------------------ |
| **激励奖励** | ✅ 已实现  | 动态计算、声誉加成       |
| **质押提权** | ⏳ Phase 2 | 质押提升排名、手续费折扣 |
| **治理投票** | ⏳ Phase 3 | DAO 治理、参数调整       |
| **价值捕获** | ⏳ Phase 4 | 手续费回购、代币销毁     |

详细设计参见 [YIDENG_TOKEN_ECONOMICS.md](YIDENG_TOKEN_ECONOMICS.md)

---

## 🚀 快速开始

### 环境要求

- Node.js >= 16.x
- pnpm / npm
- Git

### 1️⃣ 克隆项目

```bash
git clone https://github.com/your-username/aladdin-contract.git
cd aladdin-contract
```

### 2️⃣ 安装依赖

```bash
pnpm install
# 或
npm install
```

### 3️⃣ 环境配置

创建 `.env` 文件：

```bash
cp .env.example .env
```

编辑 `.env`：

```env
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
SEPOLIA_PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

### 4️⃣ 编译合约

```bash
npm run compile
```

### 5️⃣ 运行测试

```bash
npm run test:hardhat
```

期望输出：

```
✔ 46 passing
```

### 6️⃣ 部署到测试网

```bash
# 直接部署到 Sepolia，脚本会在缺省配置时自动生成测试代币
npm run deploy:sepolia
```

---

## 🧪 测试

本项目使用 **Hardhat + Foundry 风格 Solidity 测试**（.t.sol 文件）。

### 运行测试

```bash
# 运行所有测试（自动安装 forge-std）
npm run test:hardhat

# 仅运行 Solidity 测试
npm run test:sol

# 编译合约
npm run compile

# 清理缓存
npm run clean
```

### 测试覆盖

**RewardManager.t.sol** (10 个测试)

- ✅ 注册 Agent 获得 500 ALD
- ✅ 防重复领取注册奖励
- ✅ 完成任务每个 Agent 获得 500 ALD
- ✅ 防重复领取完成奖励
- ✅ 防自雇佣刷奖励
- ✅ Owner 权限管理
- ✅ 余额检查和统计

**AgentMarket.t.sol** (36 个测试)

- ✅ Agent 注册和管理
- ✅ USDT 充值托管
- ✅ 雇佣关系创建
- ✅ 支付分配计算
- ✅ 边界条件测试
- ✅ 事件触发验证

详细测试指南：[TESTING_GUIDE.md](TESTING_GUIDE.md)

## 🚀 快速开始

### 1️⃣ 首次安装依赖

```bash
# 安装 forge-std 库（用于 Solidity 测试）
npm run setup:forge

# 或手动安装
pnpm install --save-dev github:foundry-rs/forge-std#v1.9.7
```

### 2️⃣ 运行测试

```bash
# 运行所有测试（会自动安装 forge-std）
npm run test:hardhat

# 仅运行 Solidity 测试文件（*.t.sol）
npm run test:sol

# 编译合约
npm run compile

# 清理缓存
npm run clean
```

---

---

## 📦 部署

### 本地部署

```bash
# 启动本地节点
npx hardhat node

# 新终端部署
npm run deploy:local
```

> 脚本会基于当前网络自动选择 USDT 地址（Sepolia 默认指向 `0x7169...`），如网络无预设地址则自动部署临时代币。奖励代币始终由脚本自动部署。

### 测试网部署

```bash
# Sepolia 测试网
npm run deploy:sepolia
```

> Sepolia 默认使用预设 USDT 地址；其它网络若无预设地址，脚本会自动部署临时代币并提示。

### 部署流程

部署脚本 `scripts/deploy.js` 会自动完成：

1. 根据当前网络选择 USDT 地址（含预设表），并部署 `AgentMarket`；若未匹配则自动部署测试代币。
2. 自动部署新的 `AladdinToken` 作为奖励代币，并部署 `RewardManager`。
3. 部署完成后调用 `setRewardManager` 关联合约，并输出所有关键地址，供后续验证与手动资金划转。

### 合约验证

```bash
npx hardhat verify --network sepolia <CONTRACT_ADDRESS> <CONSTRUCTOR_ARGS>
```

---

## 💻 使用示例

### 示例 1: 注册 Agent 并获得奖励

```javascript
import { ethers } from "hardhat";

// 连接合约
const agentMarket = await ethers.getContractAt("AgentMarket", MARKET_ADDRESS);
const aladdinToken = await ethers.getContractAt("AladdinToken", ALD_ADDRESS);

// 准备数据
const skills = ["Solidity", "Web3", "Smart Contracts"];
const dailyRate = ethers.parseEther("100"); // 100 USDT/天

// 注册 Agent（自动获得 500 ALD）
const tx = await agentMarket.registerAgent(skills, dailyRate);
await tx.wait();

// 检查奖励
const aldBalance = await aladdinToken.balanceOf(userAddress);
console.log("获得奖励:", ethers.formatEther(aldBalance), "ALD");
// 输出: 获得奖励: 500.0 ALD
```

### 示例 2: 雇佣 Agent 并完成任务

```javascript
// 1. 雇主充值 USDT
const usdt = await ethers.getContractAt("IERC20", USDT_ADDRESS);
await usdt.approve(MARKET_ADDRESS, ethers.parseEther("1000"));
await agentMarket.deposit(ethers.parseEther("1000"));

// 2. 创建雇佣关系（雇佣 2 个 Agent，3 天）
const agentIds = [1, 2]; // Agent ID
const duration = 3; // 天数
const payment = ethers.parseEther("600"); // 600 USDT

await agentMarket.createEmployment(
  employerAddress,
  agentIds,
  duration,
  payment
);

// 3. 完成任务
await agentMarket.completeEngagement(1); // employmentId = 1

// 结果：
// - Agent 1 和 2 按费率比例分配 USDT
// - 每个 Agent 获得 500 ALD 奖励
// - 平台收取 2% 手续费
```

### 示例 3: 查询统计数据

```javascript
const rewardManager = await ethers.getContractAt(
  "RewardManager",
  REWARD_ADDRESS
);

// 奖励池余额
const poolBalance = await rewardManager.getRewardPoolBalance();
console.log("奖励池:", ethers.formatEther(poolBalance), "ALD");

// 总发放量
const totalRewards = await rewardManager.totalRewardsDistributed();
console.log("总发放:", ethers.formatEther(totalRewards), "ALD");

// 注册奖励统计
const regRewards = await rewardManager.totalRegistrationRewards();
console.log("注册奖励:", ethers.formatEther(regRewards), "ALD");
```

---

## 📚 项目文档

| 文档                                                   | 说明                  |
| ------------------------------------------------------ | --------------------- |
| [CLAUDE.md](CLAUDE.md)                                 | Claude Code 工作指南  |
| [AGENTS.md](AGENTS.md)                                 | 项目结构和开发规范    |
| [TESTING_GUIDE.md](TESTING_GUIDE.md)                   | Solidity 测试完整指南 |
| [REWARD_SYSTEM.md](REWARD_SYSTEM.md)                   | 奖励系统详细文档      |
| [YIDENG_TOKEN_ECONOMICS.md](YIDENG_TOKEN_ECONOMICS.md) | 代币经济模型设计      |

---

## 🛠️ 技术栈

### 区块链

- **Solidity**: 0.8.20
- **OpenZeppelin Contracts**: 5.4.0
- **Hardhat**: 3.0.6
- **Ethers.js**: 6.15.0

### 测试

- **Foundry Forge Std**: 1.9.7
- **Hardhat Solidity Tests**: .t.sol 文件
- **Chai**: 断言库

### 网络

- **Sepolia Testnet**: 测试部署
- **USDT**: 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06

### 开发工具

- **TypeScript**: 5.8.3
- **pnpm**: 包管理器
- **Hardhat Toolbox**: 完整开发套件

---

## 🔐 安全机制

### 合约安全

| 机制             | 实现                           |
| ---------------- | ------------------------------ |
| **重入攻击防护** | ReentrancyGuard (OpenZeppelin) |
| **访问控制**     | Ownable 权限管理               |
| **安全转账**     | SafeERC20 封装                 |
| **自定义错误**   | Gas 优化的 error 类型          |
| **输入验证**     | 所有参数完整校验               |

### 业务安全

- ✅ 注册奖励：每地址仅一次
- ✅ 完成奖励：每雇佣关系仅一次
- ✅ 自雇佣检查：防止刷奖励
- ✅ 余额检查：防止超支
- ✅ 权限控制：RewardManager 只能由 AgentMarket 调用

### 审计状态

⚠️ **未审计** - 本项目为 MVP 版本，尚未进行专业安全审计。生产环境部署前请进行审计。

---

## 🗺️ 路线图

### ✅ Phase 1: MVP（已完成）

- [x] 核心 AgentMarket 合约
- [x] 固定奖励机制（500 ALD）
- [x] USDT 托管和分配
- [x] 完整测试覆盖（46 个测试）
- [x] 部署脚本和文档

### 🚧 Phase 2: 动态激励（进行中）

- [ ] 基于任务价值的动态奖励
- [ ] 声誉系统完善
- [ ] 质押提权机制
- [ ] 手续费折扣系统

### 📅 Phase 3: DAO 治理

- [ ] 投票合约
- [ ] 参数治理（手续费率、奖励比例）
- [ ] 提案系统
- [ ] DAO 金库管理

### 🔮 Phase 4: 生态扩展

- [ ] 手续费回购 ALD
- [ ] 代币销毁机制
- [ ] 多链部署
- [ ] 外部 dApp 集成

详细设计：[YIDENG_TOKEN_ECONOMICS.md](YIDENG_TOKEN_ECONOMICS.md)

---

## 📊 合约统计

```
总合约数: 3
总测试数: 46 (全部通过)
代码覆盖: AgentMarket + RewardManager 核心功能 100%

合约大小:
├─ AladdinToken: ~2KB
├─ RewardManager: ~5KB
└─ AgentMarket: ~8KB
```

---

## 🤝 贡献

欢迎贡献代码、报告问题或提出建议！

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

### 开发规范

参见 [CLAUDE.md](CLAUDE.md) 和 [AGENTS.md](AGENTS.md)

---

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

---

## 📞 联系方式

- **项目维护者**: [Your Name]
- **邮箱**: your.email@example.com
- **GitHub Issues**: [提交问题](https://github.com/your-username/aladdin-contract/issues)

---

## 🙏 致谢

- [OpenZeppelin](https://openzeppelin.com/) - 安全合约库
- [Hardhat](https://hardhat.org/) - 开发框架
- [Foundry](https://getfoundry.sh/) - 测试工具

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star！⭐**

Made with ❤️ by Aladdin Team

</div>
