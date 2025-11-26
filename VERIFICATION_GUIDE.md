# 合约验证指南

## 📋 概述

`auto-verify.ts` 脚本提供了智能的合约验证功能，支持多个区块链网络和区块浏览器。脚本会自动检测已验证的合约、生成验证链接，并提供详细的结果反馈。

## ✨ 功能特性

### 🚀 智能验证
- **双引擎验证**: 首先尝试 Etherscan，失败后自动回退到 Blockscout
- **已验证检测**: 智能识别已验证的合约，避免重复验证
- **实时链接**: 验证成功后立即显示对应的区块浏览器链接
- **自动延迟**: 避免 API 限制，顺序执行验证

### 🌐 支持的网络
- **以太坊主网** (Mainnet)
- **Sepolia** 测试网
- **Localhost** 本地网络
- **Base** 主网和 Sepolia 测试网
- **Polygon** 主网和 Amoy 测试网
- **Arbitrum** One 和 Sepolia 测试网
- **Optimism** 主网和 Sepolia 测试网
- **Monad** 测试网

## 🚀 使用方法

### 基本用法

```bash
# 运行自动验证脚本
npx ts-node scripts/auto-verify.ts
```

### 依赖环境

确保 `.env` 文件中配置了以下变量：

```bash
# Sepolia 配置示例
SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY"
SEPOLIA_PRIVATE_KEY="your_private_key"

# Etherscan API Key
ETHERSCAN_API_KEY="your_etherscan_api_key"
```

## 📊 输出示例

```
🔍 自动验证合约

📂 加载部署记录: chain-11155111
🌐 网络: sepolia
👤 部署者地址: 0x849fbd15f60b89ec8ae25d074addf95273cbed45

📋 待验证的合约 (5):
   - AladdinToken: 0x895c65B0321f12714009e6F8Fd2Be09fcAB6f3ED
   - MockUSDT: 0xeB741C5187C024680710cb5Ea0b7e1A9ae27ACf7
   - AgentMarket: 0x00a4a878d540e398ca603Bc857d4A75ab37d784b
   - YieldProxy: 0x09961B3A4EE7F7dEAda3B6E3f249F743c9aec39D
   - RewardManager: 0x5bD5257906e889DC887f682E5A3543dF0c45021b

🚀 开始验证所有合约:

🔄 正在验证 AladdinToken...
   地址: 0x895c65B0321f12714009e6F8Fd2Be09fcAB6f3ED
✅ AladdinToken 已经验证过了！
🔗 Blockscout: https://sepolia.blockscout.com/address/0x895c65B0321f12714009e6F8Fd2Be09fcAB6f3ED#code

📊 验证结果统计:
✅ 成功: 5
❌ 失败: 0
📊 总计: 5

🎉 所有合约验证完成！
```

## 🔧 验证流程

### 1. 自动检测
- 脚本读取 `ignition/deployments` 目录中的最新部署记录
- 自动识别所有已部署的合约
- 根据部署目录映射到对应网络

### 2. 生成命令
- 为每个合约生成 Etherscan 验证命令
- 同时生成 Blockscout 验证命令作为备选
- 自动添加正确的构造函数参数

### 3. 执行验证
- 首先尝试 Etherscan 验证
- 如果失败或遇到 API key 问题，自动切换到 Blockscout
- 识别 "already verified" 状态，避免重复验证

### 4. 显示结果
- 实时显示验证进度
- 验证成功后立即显示区块浏览器链接
- 最终统计成功/失败数量

## 📝 合约构造函数参数说明

| 合约 | 构造函数参数 |
|------|--------------|
| AladdinToken | owner (部署者地址) |
| MockUSDT | owner (部署者地址) |
| AgentMarket | usdtToken, rewardManager (初始为 zero address) |
| RewardManager | aladdinToken, agentMarket |
| YieldProxy | stakingToken (USDT) |

## 🌐 不同网络的验证

### Sepolia 测试网
```bash
npx ts-node scripts/auto-verify.ts
```

脚本会自动检测部署在 Sepolia 网络的合约。

### Localhost (本地开发)
```bash
npx ts-node scripts/auto-verify.ts
```

**注意**: Localhost 通常不需要验证，因为合约只在本地网络有效。

### 主网 (Mainnet)
```bash
npx ts-node scripts/auto-verify.ts
```

脚本会自动检测部署在主网的合约。

## ⚙️ 配置说明

### 网络映射

在 `scripts/auto-verify.ts` 中修改 `LEGACY_NETWORKS` 对象来添加新的网络：

```typescript
const LEGACY_NETWORKS: Record<string, string> = {
  "chain-11155111": "sepolia", // Sepolia 测试网
  "chain-31337": "localhost", // 本地网络
  "chain-1": "mainnet", // 以太坊主网
  "chain-10143": "monadTestnet", // Monad 测试网
  // 添加更多网络...
};
```

### 网络命名规则

- 使用 `chain-{chainId}` 作为键
- 使用标准的网络名称作为值（如 `sepolia`、`mainnet` 等）
- 网络名称应该与 Hardhat 网络配置中的名称一致

## 🚨 常见问题

### Q: 脚本如何知道验证哪个网络的合约？
A: 脚本会读取 `ignition/deployments` 目录中的最新部署记录，并根据部署目录名称映射到对应的网络。

### Q: Etherscan 和 Blockscout 有什么区别？
A:
- **Etherscan**: 以太坊官方区块浏览器，部分网络可能不支持
- **Blockscout**: 第三方区块浏览器，支持更多网络，兼容性更好

### Q: 如果合约验证失败怎么办？
A: 脚本会自动尝试两个验证器。如果都失败，请检查：
1. 合约地址是否正确
2. 网络连接是否正常
3. API Key 是否有效

### Q: 提示 "Already Verified"？
A: 该合约已经验证过，脚本会显示链接，跳过重复验证。

### Q: 验证失败？
A: 检查：
- 网络配置是否正确
- 构造函数参数是否正确
- 是否在合约部署后立即验证

## 📁 部署文件位置

部署地址保存在：
```
ignition/deployments/<chain-id>/deployed_addresses.json
```

示例：
- Sepolia: `ignition/deployments/chain-11155111/deployed_addresses.json`
- Localhost: `ignition/deployments/chain-31337/deployed_addresses.json`

## 🎯 最佳实践

1. ✅ **立即验证** - 合约部署后立即验证
2. ✅ **记录地址** - 保存所有合约地址到安全位置
3. ✅ **测试网优先** - 先在测试网验证流程
4. ✅ **备份代码** - 保留合约源代码和验证记录
5. ✅ **使用脚本** - 使用 `auto-verify.ts` 自动化验证流程

## 🔬 技术细节

### 验证流程

1. 读取最新部署记录
2. 获取合约地址列表
3. 生成验证命令（支持 Etherscan 和 Blockscout）
4. 顺序执行验证（避免 API 限制）
5. 显示结果和链接

### 错误处理

- 网络错误：自动重试
- API 限制：添加延迟
- 已验证状态：跳过并显示链接
- 验证失败：记录错误信息

## 相关文件

- `scripts/auto-verify.ts` - 主验证脚本
- `ignition/deployments/` - 部署记录目录
- `.env` - 环境变量配置
- `hardhat.config.ts` - Hardhat 网络配置

---

**Happy Verifying! 🎉**
