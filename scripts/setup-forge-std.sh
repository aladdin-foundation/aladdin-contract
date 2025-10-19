#!/bin/bash

# 安装 forge-std 用于 Hardhat Solidity 测试
# 参考: https://hardhat.org/docs/learn-more/writing-solidity-tests

echo "📦 正在安装 forge-std 库..."

# 检查是否已安装
if [ -d "node_modules/forge-std" ]; then
    echo "✅ forge-std 已安装，跳过"
    exit 0
fi

# 使用 pnpm 安装（如果可用），否则使用 npm
if command -v pnpm &> /dev/null; then
    echo "使用 pnpm 安装..."
    pnpm install --save-dev github:foundry-rs/forge-std#v1.9.7
elif command -v npm &> /dev/null; then
    echo "使用 npm 安装..."
    npm install --save-dev github:foundry-rs/forge-std#v1.9.7
else
    echo "❌ 错误: 未找到 npm 或 pnpm"
    exit 1
fi

echo "✅ forge-std 安装完成"
