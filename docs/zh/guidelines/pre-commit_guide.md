# Pre-commit 配置指导书

## 概述

pre-commit 是一个 Git Hooks 框架，用于在 `git commit` 时自动运行代码检查和格式化工具。本项目已配置以下检查：

| Hook | 功能 | 说明 |
|------|------|------|
| **clang-format** | C/C++ 代码格式化 | 自动格式化代码，保持风格一致 |
| **OAT Check** | 开源合规检查 | 检测许可证头、禁止二进制文件提交 |

## 环境要求

- **Git**: 2.0+
- **Python**: 3.8+
- **clang-format**: 14.0+ (代码格式化)

## 安装步骤

### 1. 安装 pre-commit

```bash
# 方式一: 使用 pip
pip install pre-commit

# 方式二: 使用系统包管理器 (Ubuntu/Debian)
sudo apt install pre-commit
```

### 2. 安装依赖工具

```bash
# Ubuntu/Debian
sudo apt install clang-format

# macOS
brew install clang-format
```

### 3. 项目路径下安装 Git Hooks

```bash
cd /path/to/runtime
pre-commit install
```

安装成功后会显示：

```text
pre-commit installed at .git/hooks/pre-commit
```

## 使用方法

### 自动检查（推荐）

每次执行 `git commit` 时，pre-commit 会自动运行检查：

```bash
git add .
git commit -m "your commit message"
```

输出示例：

```text
clang-format.............................................................Passed
OAT Compliance Check (Python Edition).....................................Passed
```

### 手动运行检查

```bash
# 运行所有检查
pre-commit run

# 运行特定类型检查
pre-commit run clang-format
pre-commit run oat-check

# 检查所有文件（不限于暂存区）
pre-commit run --all-files
```

### 跳过检查（紧急情况）

```bash
git commit --no-verify -m "emergency fix"
```

> **注意**: 仅在紧急情况下使用，正常开发流程应保证检查通过。

## 检查项说明

### 1. clang-format

自动格式化 C/C++ 代码，遵循项目 `.clang-format` 配置：

- **缩进**: 4 空格
- **列宽**: 120 字符
- **大括号**: 函数定义换行，控制语句同行
- **指针对齐**: 右对齐 (`int *ptr`)

### 2. OAT Compliance Check

OAT (Open Source Audit Tool) 检查开源合规性：

| 检查项 | 说明 |
|--------|------|
| 许可证头检查 | 确保源文件包含 CANN License 头 |
| 二进制文件检查 | 禁止提交二进制文件 |
| 归档文件检查 | 禁止提交 zip/tar 等归档文件 |

OAT 使用 [compliance](https://gitcode.com/HiAgent/compliance) 仓库提供的远程 Python hook，版本由 `.pre-commit-config.yaml` 中的 `rev: v1.0.6` 固定。首次运行时，pre-commit 会自动克隆该仓库，在独立的 Python 虚拟环境中安装 OAT 及其依赖，并通过 `oat-precommit` 检查传入的文件。

仓库根目录的 `OAT.xml` 用于配置本项目的合规规则，无需复制或维护本地检查脚本。

## 常见问题

### Q1: 首次提交时 OAT 检查很慢

**原因**: 首次运行需要下载远程 hook 并安装 Python 环境及依赖，需要能够访问 GitCode 和 Python 包源。

**解决**: 等待首次安装完成，后续提交会复用 pre-commit 缓存的环境。

## 相关文档

- [pre-commit 官方文档](https://pre-commit.com/)
- [clang-format 配置](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)
- [OAT 远程 hook](https://gitcode.com/HiAgent/compliance)
- [代码仓集成pre-commit指导](https://gitcode.com/cann/infrastructure/blob/main/docs/SC/pre-commit/pre-commit%E9%85%8D%E7%BD%AE%E6%8C%87%E5%AF%BC%E4%B9%A6.md)
