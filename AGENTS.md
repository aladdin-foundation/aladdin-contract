# Repository Guidelines

## 项目结构与模块组织

- `contracts/`：核心 Solidity 合约所在目录，`AgentMarket.sol` 负责雇佣撮合逻辑，`AladdinToken.sol` 提供测试用 ERC20；新增合约时保持单一职责，并在文件顶部注明 SPDX 与编译版本。
- `test/`：存放 Foundry `.t.sol` 测试，例如 `AgentMarket.t.sol`；扩展 Hardhat TypeScript 测试时使用 `test/ts` 子目录避免冲突。
- `scripts/`：部署与维护脚本，`deploy.js` 会基于网络选择预设 USDT 地址（Sepolia 默认 `0x7169...`），若无匹配则自动部署测试代币，同时部署奖励代币并完成 `AgentMarket`+`RewardManager` 绑定。
- `ignition/modules/`：Ignition 部署模块示例，建议仿照 `CounterModule` 编写并在模块返回结构体里暴露部署结果。
- `artifacts/` 与 `cache/` 为 Hardhat 输出目录，禁止手动修改；需要清理时运行 `npx hardhat clean`。
- `README.md` 与 `AGENTS.md` 汇总公共文档，新增流程或架构决策时请同步两份文件，保持新成员可快速上手。

## 构建、测试与开发命令

- `pnpm install`：安装依赖，推荐 Node.js 18 或更高版本。
- `pnpm test`：使用 Foundry 运行 `.t.sol` 单元测试；首次执行前请确保通过 `foundryup` 安装工具链。
- `pnpm run test:hardhat`：调用 Hardhat 的 TypeScript 测试套件，适用于端到端或脚本级验证。
- `npx hardhat compile`：编译所有 Solidity 合约并刷新 `artifacts/`。
- `npx hardhat node` + `npx hardhat run scripts/deploy.js --network localhost`：启动本地区块链并部署最新合约；本地网络将自动部署测试代币与奖励代币。
- `npm run deploy:local` / `npm run deploy:sepolia`：脚本自动使用预设 USDT 地址（或部署测试代币），并同时部署奖励代币。

## 编码风格与命名约定

- Solidity 采用四空格缩进，合约命名使用 `PascalCase`，状态变量与函数使用 `camelCase`，常量以 `UPPER_SNAKE_CASE` 表示。
- 所有外部或公共函数需补充 NatSpec 注释，描述参数、返回值与潜在安全注意事项。
- TypeScript/JavaScript 脚本保持 ESLint 推荐风格，导入顺序为 Node 内置、第三方、项目内模块；格式化使用 `pnpm exec prettier --write`。

## 测试指引

- 首选工具链为 Foundry `forge test`，断言库使用 `forge-std/Test.sol`；Hardhat 测试可作为补充验证脚本行为。
- 新增功能至少覆盖成功路径、参数验证失败与事件触发三类场景；关键结算与权限逻辑追求 100% 分支覆盖。
- 测试函数命名遵循 `test_<行为描述>`，例如 `test_CompleteEngagement_ShouldPayAgents`，便于 CI 日志检索。
- 针对复杂资金分配或权限矩阵，建议使用 `vm.prank`、`vm.warp` 等作弊码模拟多角色与时间推进，保证逻辑可被稳定复现。

## 提交与拉取请求规范

- 提交信息沿用历史风格，使用英文小写动词开头的短句，如 `update agent payout logic`；涉及合约接口请追加作用域前缀。
- PR 描述需包含变更摘要、测试结果（命令输出或截图）及关联 Issue；如影响部署流程，补充需要更新的网络与参数。
- 在 PR 对话内附加安全评估或 gas 估算，确保审核者掌握成本影响。

## 安全与配置提示

- 所有私钥与 RPC 配置存放于 `.env`，通过 `.env.example` 模板同步变量；提交前使用 `git status --short` 确认未误传敏感文件。
- 部署前校验 `feePercentage` 与其他经济参数是否符合最新运营策略，必要时在 PR 中列出调整理由。
- 依赖升级后执行 `pnpm audit` 与 `forge test`，并在变更说明中写明潜在破坏性更新或所需迁移步骤。
