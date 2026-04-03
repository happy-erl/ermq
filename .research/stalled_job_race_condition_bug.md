# Bug 发现报告：竞态条件导致本应取消的任务被重新执行

## 1. Bug 概述

在 `moveStalledJobsToWait-8.lua` 脚本中发现了一个严重的竞态条件（Race Condition）漏洞，导致本应被取消或失败的任务会被重新添加到等待队列中执行。

## 2. Bug 详情

### 2.1 问题位置

**文件**: `moveStalledJobsToWait-8.lua`

### 2.2 问题描述

当前 `moveStalledJobsToWait` 脚本存在一个关键的时间窗口竞态条件：

```lua
-- 步骤1: 获取所有可能的卡住作业
local active = rcall('LRANGE', activeKey, 0, -1)

-- 步骤2: 将这些作业添加到 stalled set
if (#active > 0) then
    for from, to in batches(#active, 7000) do
        rcall('SADD', stalledKey, unpack(active, from, to))
    end
end
```

**竞态条件时间线**:

```
时间 T0: Worker A 从 wait 队列取出 Job X，添加到 active 队列
时间 T1: Worker A 开始处理 Job X（尚未设置锁）
时间 T2: moveStalledJobsToWait 扫描 active 队列，将 Job X 添加到 stalled set
时间 T3: Worker A 设置锁（Job X 现在有锁了）
时间 T4: Worker A 完成处理，将 Job X 移到 completed
时间 T5: moveStalledJobsToWait 检查 stalled set 中的 Job X
         - 此时 Job X 的锁已被删除
         - Job X 也不在 active 队列中了
         - 但 Job X 可能被当成"stalled"作业重新处理！
```

### 2.3 具体问题分析

脚本在判断一个作业是否为"stalled"时的逻辑是：

```lua
-- 检查锁是否不存在
if (rcall("EXISTS", jobKey .. ":lock") == 0) then
    -- 从 active 队列移除
    local removed = rcall("LREM", activeKey, 1, jobId)
    if (removed > 0) then  -- 问题：这里才检查是否成功移除
        ...
    end
end
```

**问题**:
1. 如果一个作业已经完成并被移出了 active 队列，`LREM` 会返回 0
2. 但如果作业刚好被其他 worker 处理（锁被移除后又重新获取），这个检查就会失败

## 3. 第二个 Bug：父作业失败处理逻辑错误

### 3.1 问题位置

**文件**: `includes/moveParentToWait.lua` 和 `includes/moveChildFromDependenciesIfNeeded.lua`

### 3.2 问题描述

在 `moveChildFromDependenciesIfNeeded.lua` 的 `moveParentToFailedIfNeeded` 函数中：

```lua
local moveParentToFailedIfNeeded = function (parentQueueKey, parentKey, parentId, jobIdKey, timestamp)
  if rcall("EXISTS", parentKey) == 1 then
    local parentWaitingChildrenKey = parentQueueKey .. ":waiting-children"
    ...
    if rcall("ZSCORE", parentWaitingChildrenKey, parentId) then
      ...
      rcall("ZREM", parentWaitingChildrenOrDelayedKey, parentId)
      ...
      -- BUG: 这里调用 moveParentToWait 而不是让作业保持在失败状态！
      moveParentToWait(parentQueueKey, parentKey, parentId, timestamp)
    else
      ...
    end
  end
end
```

**问题**: 当子作业失败且配置了 `fpof`（fail parent on fail）时，父作业应该被标记为失败，但代码却调用了 `moveParentToWait`，将父作业重新添加到等待队列中！这导致父作业被重新执行而不是失败。

## 4. 第三个 Bug：updateParentDepsIfNeeded 竞态条件

### 4.1 问题位置

**文件**: `includes/updateParentDepsIfNeeded.lua`

### 4.2 问题描述

```lua
local function updateParentDepsIfNeeded(parentKey, parentQueueKey, parentDependenciesKey,
  parentId, jobIdKey, returnvalue, timestamp )
  local processedSet = parentKey .. ":processed"
  rcall("HSET", processedSet, jobIdKey, returnvalue)
  -- 问题：没有再次检查依赖状态就直接移动父作业
  moveParentToWaitIfNoPendingDependencies(parentQueueKey, parentDependenciesKey, parentKey, parentId, timestamp)
end
```

问题在于：当多个子作业几乎同时完成时，可能会出现以下竞态条件：

```
时间 T1: Job A 完成，进入 moveToFinished
时间 T2: Job A 的 moveToFinished 将结果写入 processed set
时间 T3: Job B 完成，进入 moveToFinished  
时间 T4: Job B 的 moveToFinished 也触发 updateParentDepsIfNeeded
时间 T5: 两个脚本都检测到 SCARD == 0
时间 T6: 两个脚本都调用 moveParentToWait，导致父作业被添加两次！
```

## 5. 第四个 Bug：作业删除不彻底导致重复执行

### 5.1 问题位置

**文件**: `includes/removeJobWithChildren.lua` 和 `includes/removeJobFromAnyState.lua`

### 5.2 问题描述

```lua
local function removeJobWithChildren(prefix, jobId, parentKey, options)
    local jobKey = prefix .. jobId
    
    if options.ignoreLocked then
        if isLocked(prefix, jobId) then
            return  -- 如果作业被锁定，直接返回而不删除
        end
    end
    ...
end
```

当 `ignoreLocked` 选项为 true 时，如果作业当前被锁定（正在被 worker 处理），删除操作会直接返回，但作业仍然保留在 active 队列中。这会导致：
1. 作业不会被删除
2. worker 会继续处理这个本应被取消的作业
3. 即使作业被标记为要删除，它完成后仍会被添加到完成队列

## 6. 根本原因分析

### 6.1 设计缺陷

1. **锁机制不完善**: `prepareJobForProcessing` 在作业数据更新后才设置锁，导致时间窗口存在
2. **状态检查非原子性**: 多个脚本对作业状态的检查不是完全原子的
3. **错误恢复逻辑不完整**: 某些错误情况下缺少正确的回滚机制

### 6.2 并发控制不足

当多个 worker 或脚本同时操作同一个作业时，没有足够的机制保证一致性。

## 7. 建议修复方案

### 7.1 修复 moveStalledJobsToWait

```lua
-- 在检查 stalled 作业时，增加更严格的验证
if (rcall("EXISTS", jobKey .. ":lock") == 0) then
    local removed = rcall("LREM", activeKey, 1, jobId)
    if (removed > 0) then
        -- 只有成功从 active 移除的作业才算真正的 stalled
        -- 继续处理...
    else
        -- 作业已不在 active 中，可能已完成或被其他 worker 处理
        -- 从 stalled set 中移除（如果存在）
        rcall("SREM", stalledKey, jobId)
    end
end
```

### 7.2 修复 moveParentToFailedIfNeeded

将 `moveParentToWait` 调用替换为将父作业移动到失败状态的逻辑：

```lua
if rcall("ZSCORE", parentWaitingChildrenKey, parentId) then
    ...
    rcall("ZREM", parentWaitingChildrenOrDelayedKey, parentId)
    local deferredFailure = "child " .. jobIdKey .. " failed"
    rcall("HSET", parentKey, "defa", deferredFailure)
    -- 不应该调用 moveParentToWait，而应该添加到 failed 集合
    rcall("ZADD", parentFailedKey, timestamp, parentId)
end
```

### 7.3 修复 updateParentDepsIfNeeded 竞态

在调用 `moveParentToWaitIfNoPendingDependencies` 前增加原子性检查：

```lua
-- 使用 WATCH/MULTI/EXEC 保证原子性
-- 或者在 Lua 脚本中增加额外的存在性检查
if rcall("ZREM", parentWaitingChildrenKey, parentId) == 1 then
    -- 只有成功移除的情况下才移动
    moveParentToWait(...)
end
```

### 7.4 修复作业删除逻辑

对于要删除但正在被处理的作业，应该：
1. 标记作业为"待删除"状态
2. 当作业完成时，直接移入完成/失败队列后立即删除
3. 而不是等待 worker 完成后再处理

## 8. 影响范围

- **安全性**: 高 - 可能导致任务重复执行，产生数据不一致
- **可靠性**: 高 - 本应失败的任务可能被错误地重新执行
- **数据完整性**: 高 - 作业状态可能出现不一致