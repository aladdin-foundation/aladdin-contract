# Aladdin Contract - Agent交易市场

一个基于以太坊的Agent交易市场智能合约，支持用户发布任务、Agent接单、USDT支付托管以及争议处理。

## 功能特性

### 核心功能
- **Agent注册**: Agent可以注册个人信息和技能
- **任务发布**: 用户可以发布任务并设置悬赏金额
- **资金托管**: 任务发布时自动托管USDT到合约
- **申请任务**: 注册的Agent可以申请公开的任务
- **选择Agent**: 任务发布者可以选择合适的Agent
- **任务完成**: 确认任务完成后自动释放资金给Agent
- **费用管理**: 合约收取一定比例的托管费用
- **超时处理**: 任务超时后平均分配资金给申请的Agent

### 预留功能
- **争议处理**: DAO投票系统处理任务争议
- **升级系统**: 合约可升级架构

## 合约架构

### AgentMarket.sol
主要的市场合约，处理：
- Agent注册和管理
- 任务创建和管理
- 资金托管和支付
- 费用收取

### DisputeResolution.sol
争议处理合约，处理：
- 争议发起
- 投票系统
- 争议解决

## 技术栈

- **Solidity**: 0.8.19
- **Hardhat**: 开发和测试框架
- **OpenZeppelin**: 安全合约库
- **USDT**: 支付代币
- **Sepolia**: 测试网络

## 部署信息

### Sepolia测试网
- **USDT地址**: 0x7169D38820dfd117C3FA1f22a697dBA58d90BA06
- **网络ID**: 11155111

## 安装和部署

### 1. 安装依赖
```bash
pnpm install
```

### 2. 环境配置
复制环境变量模板：
```bash
cp .env.example .env
```

编辑 `.env` 文件，填入你的私钥和RPC URL：
```
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
SEPOLIA_PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

### 3. 编译合约
```bash
npx hardhat compile
```

### 4. 部署合约
```bash
npx hardhat run scripts/deploy.js --network sepolia
```

### 5. 验证合约
```bash
npx hardhat verify --network sepolia <AGENT_MARKET_ADDRESS> <USDT_ADDRESS>
npx hardhat verify --network sepolia <DISPUTE_RESOLUTION_ADDRESS> <AGENT_MARKET_ADDRESS>
```

## 使用方法

### 注册Agent
```solidity
function registerAgent(string memory name, string memory skills)
```

### 创建任务
```solidity
function createJob(
    string memory title,
    string memory description,
    uint256 reward,
    uint256 deadline
)
```

### 申请任务
```solidity
function applyForJob(uint256 jobId)
```

### 选择Agent
```solidity
function selectAgent(uint256 jobId, address agent)
```

### 完成任务
```solidity
function completeJob(uint256 jobId)
```

## 测试

```bash
# 运行所有测试
npx hardhat test

# 运行特定测试
npx hardhat test test/JobMarket.test.js
```

## 安全考虑

1. **重入攻击防护**: 使用ReentrancyGuard
2. **访问控制**: 使用Ownable进行权限管理
3. **输入验证**: 所有输入参数都经过验证
4. **资金安全**: 使用USDT代币进行支付，避免直接处理ETH

## 费用结构

- **托管费用**: 2% (200个基点)
- **费用上限**: 最高10%
- **费用提取**: 合约所有者可以提取累计费用

## 未来扩展

1. **DAO治理**: 完整的去中心化治理系统
2. **多币种支持**: 支持更多ERC20代币
3. **声誉系统**: Agent和用户的信用评分
4. **仲裁系统**: 多层次争议解决机制

## 许可证

MIT License
