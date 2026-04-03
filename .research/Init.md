# ERMQ 学习和发现报告

## 1. 项目概述

ERMQ 是一个基于 Redis 的消息队列系统，它是 BullMQ（Node.js）的 Erlang 端口实现。它使用 Lua 脚本来保证原子性操作。

## 2. 系统架构

### 2.1 组件结构

```
ERMQ/
├── src/                    # Erlang 源代码
│   ├── ermq.erl           # 主模块（空）
│   ├── ermq_job.erl       # 作业管理
│   ├── ermq_redis.erl     # Redis 连接封装
│   ├── ermq_scripts.erl   # Lua 脚本管理器
│   ├── ermq_config.erl    # 配置管理
│   ├── ermq_utils.erl     # 工具函数
│   ├── ermq_msgpack.erl   # MessagePack 编码器
│   └── ermq_errors.erl    # 错误定义
├── priv/lua/              # Lua 脚本
│   ├── includes/          # 可复用的 Lua 函数
│   └── *.lua              # 主 Lua 脚本
└── test/                  # 测试文件
```

### 2.2 核心模块说明

#### ermq_job.erl
- 负责作业的创建、添加和检索
- 通过 Lua 脚本将作业添加到 Redis
- 支持标准作业、延迟作业和优先级作业

#### ermq_redis.erl
- 使用 `eredis` 库进行 Redis 通信
- 提供 `command/2` 和 `pipeline/2` 接口
- 支持别名 `q/2` 和 `qp/2`

#### ermq_scripts.erl
- 管理 Lua 脚本的加载和缓存
- 使用 ETS 表缓存脚本 SHA1
- 支持 `@include` 指令
- 自动处理 NOSCRIPT 错误并重试

#### ermq_msgpack.erl
- 自实现的 MessagePack 编码器
- 用于在 Lua 脚本间传递复杂参数
- 支持整数、浮点数、二进制、原子、列表和映射

## 3. 作业状态和流程

### 3.1 作业状态

```
                    ┌────────────┐
                    │   wait     │◄──┐
                    └─────┬──────┘   │
                          │          │
                          ▼          │
    ┌─────────┐    ┌──────────────┐  │
    │ delayed │───►│   active     │──┤
    └─────────┘    └──────┬───────┘  │
                          │          │
                    ┌─────▼──────┐   │
                    │ completed  │   │
                    │   failed   │   │
                    └────────────┘   │
                                     │
                    ┌────────────────┘
                    ▼
          ┌─────────────────┐
          │waiting-children│
          └─────────────────┘
```

### 3.2 关键流程

#### 作业添加 (addStandardJob/addDelayedJob/addPrioritizedJob)
1. 在 `{prefix}:{jobId}` 键中存储作业数据
2. 将作业 ID 放入相应的队列（wait/delayed/prioritized）
3. 在事件流中发出事件

#### 作业处理 (moveToActive)
1. 首先检查是否有延迟作业可以提升到 wait 队列
2. 检查速率限制
3. 检查队列是否暂停或达到上限
4. 从 wait 队列移动到 active 队列
5. 设置锁
6. 返回作业数据

#### 作业完成 (moveToFinished)
1. 验证作业存在
2. 移除锁
3. 从 active 队列移除
4. 处理父子作业依赖关系
5. 添加到 completed/failed 集合
6. 发出事件
7. 可选地获取下一个作业

#### 作业重试 (retryJob)
1. 从 active 队列移除
2. 添加到 wait 队列（考虑优先级）
3. 发出 waiting 事件

#### 卡住作业恢复 (moveStalledJobsToWait)
1. 检查 stalled 集合中的所有作业
2. 对于没有锁的作业，移回 wait 队列
3. 标记 active 队列中的作业为可能卡住

## 4. Lua Includes 分析

### 4.1 核心函数

#### prepareJobForProcessing
- 设置速率限制计数器
- 设置作业锁（如果 token != "0"）
- 更新 processedOn 和尝试次数
- 返回作业数据

#### removeJobFromAnyState
- 从任何状态集合中移除作业
- 按顺序检查：completed, waiting-children, delayed, failed, prioritized, wait, paused, active

#### moveParentToWaitIfNeeded/IfNoPendingDependencies
- 当子作业完成时，检查父作业是否可以移动到 wait 队列
- 处理跨队列的父子关系

### 4.2 作业移除

#### removeJobWithChildren
- 递归移除作业及其子作业
- 支持 ignoreProcessed 和 ignoreLocked 选项

#### removeParentDependencyKey
- 移除子作业对父作业的依赖
- 如果所有依赖完成，将父作业移动到 wait 队列

## 5. 数据结构

### 5.1 Redis 键结构

```
{prefix}:{queueName}
├── wait           - 等待队列（LIST）
├── active         - 活动队列（LIST）
├── paused         - 暂停队列（LIST）
├── delayed        - 延迟作业（ZSET）
├── prioritized    - 优先级作业（ZSET）
├── completed      - 已完成作业（ZSET）
├── failed         - 已失败作业（ZSET）
├── waiting-children - 等待子作业（ZSET）
├── stalled        - 卡住作业（SET）
├── meta           - 队列元数据（HASH）
├── events         - 事件流（STREAM）
├── events:opts    - 事件选项
├── marker         - 标记键
├── id             - 作业 ID 计数器
├── {jobId}        - 作业数据（HASH）
│   ├── data       - 作业数据（JSON）
│   ├── opts       - 作业选项（JSON）
│   ├── priority   - 优先级
│   ├── delay      - 延迟时间
│   ├── attempts   - 最大尝试次数
│   ├── atm        - 已尝试次数
│   ├── stc        - 卡住计数
│   ├── processedOn - 处理时间
│   ├── finishedOn  - 完成时间
│   ├── defa       - 失败原因
│   ├── returnvalue - 返回值
│   ├── parentKey   - 父作业键
│   ├── parent      - 父作业信息（JSON）
│   ├── deid        - 去重 ID
│   ├── {jobId}:lock - 作业锁
│   ├── {jobId}:dependencies - 依赖关系（SET）
│   ├── {jobId}:processed - 处理结果（HASH）
│   ├── {jobId}:failed - 失败结果（HASH）
│   └── {jobId}:unsuccessful - 未成功记录（ZSET）
```

## 6. 配置

### 6.1 队列选项
```erlang
#{
    prefix => <<"ermq">>,        % Redis 键前缀
    connection => #{},            % Redis 连接配置
    defaultJobOptions => #{}      % 默认作业选项
}
```

### 6.2 作业选项
```erlang
#{
    attempts => 1,                % 最大尝试次数
    delay => 0,                   % 延迟时间（毫秒）
    timestamp => os:system_time(millisecond),  % 时间戳
    priority => undefined,        % 优先级
    jobId => undefined            % 自定义作业 ID
}
```

## 7. 测试发现

### 7.1 已知问题
运行测试时发现 4 个失败：
1. `test_job_retrieval` - not_found 错误
2. `test_add_delayed_job` - WRONGTYPE 错误
3. `test_add_prioritized_job` - WRONGTYPE 错误
4. `test_update_progress` - 值不匹配

这些失败可能与 Redis 数据状态有关，残留数据可能导致类型错误。

## 8. 潜在问题总结

### 8.1 竞态条件
- `moveStalledJobsToWait` 在检查锁和移动作业之间可能存在竞态
- job 删除和状态更新之间可能存在时间窗口

### 8.2 逻辑问题
- `moveToFinished` 中对子作业的处理可能导致父作业被重新激活
- `removeJobWithChildren` 在处理大量子作业时可能引发性能问题

### 8.3 边界情况
- 空列表和不存在键的处理不完全一致
- 某些脚本在作业不存在时的错误处理不够完善