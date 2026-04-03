# Bug Discovery Report: Race Condition Causing Cancelled Tasks to Be Re-executed

## 1. Bug Overview

A critical race condition vulnerability was discovered in the `moveStalledJobsToWait-8.lua` script, causing tasks that should have been cancelled or failed to be re-added to the waiting queue for execution.

## 2. Bug Details

### 2.1 Problem Location

**File**: `moveStalledJobsToWait-8.lua`

### 2.2 Problem Description

The current `moveStalledJobsToWait` script has a critical time window race condition:

```lua
-- Step 1: Get all potentially stalled jobs
local active = rcall('LRANGE', activeKey, 0, -1)

-- Step 2: Add these jobs to stalled set
if (#active > 0) then
    for from, to in batches(#active, 7000) do
        rcall('SADD', stalledKey, unpack(active, from, to))
    end
end
```

**Race Condition Timeline**:

```
Time T0: Worker A takes Job X from wait queue, adds to active queue
Time T1: Worker A starts processing Job X (lock not yet set)
Time T2: moveStalledJobsToWait scans active queue, adds Job X to stalled set
Time T3: Worker A sets lock (Job X now has lock)
Time T4: Worker A completes processing, moves Job X to completed
Time T5: moveStalledJobsToWait checks Job X in stalled set
         - Job X's lock has been deleted
         - Job X is no longer in active queue
         - But Job X may be treated as "stalled" and reprocessed!
```

### 2.3 Specific Problem Analysis

The script's logic for determining if a job is "stalled":

```lua
-- Check if lock doesn't exist
if (rcall("EXISTS", jobKey .. ":lock") == 0) then
    -- Remove from active queue
    local removed = rcall("LREM", activeKey, 1, jobId)
    if (removed > 0) then  -- Problem: only checks successful removal here
        ...
    end
end
```

**Problem**:
1. If a job has already completed and been removed from active queue, `LREM` returns 0
2. But if a job is being processed by another worker (lock removed then reacquired), this check fails

## 3. Second Bug: Parent Job Failure Handling Logic Error

### 3.1 Problem Location

**File**: `includes/moveParentToWait.lua` and `includes/moveChildFromDependenciesIfNeeded.lua`

### 3.2 Problem Description

In `moveChildFromDependencies.lua`'s `moveParentToFailedIfNeeded` function:

```lua
local moveParentToFailedIfNeeded = function (parentQueueKey, parentKey, parentId, jobIdKey, timestamp)
  if rcall("EXISTS", parentKey) == 1 then
    local parentWaitingChildrenKey = parentQueueKey .. ":waiting-children"
    ...
    if rcall("ZSCORE", parentWaitingChildrenKey, parentId) then
      ...
      rcall("ZREM", parentWaitingChildrenOrDelayedKey, parentId)
      ...
      -- BUG: Calls moveParentToWait instead of keeping job in failed state!
      moveParentToWait(parentQueueKey, parentKey, parentId, timestamp)
    else
      ...
    end
  end
end
```

**Problem**: When a child job fails and `fpof` (fail parent on fail) is configured, the parent job should be marked as failed, but the code calls `moveParentToWait`, re-adding the parent job to the waiting queue! This causes the parent job to be re-executed instead of failed.

## 4. Third Bug: updateParentDepsIfNeeded Race Condition

### 4.1 Problem Location

**File**: `includes/updateParentDepsIfNeeded.lua`

### 4.2 Problem Description

```lua
local function updateParentDepsIfNeeded(parentKey, parentQueueKey, parentDependenciesKey,
  parentId, jobIdKey, returnvalue, timestamp )
  local processedSet = parentKey .. ":processed"
  rcall("HSET", processedSet, jobIdKey, returnvalue)
  -- Problem: Moves parent job directly without rechecking dependency status
  moveParentToWaitIfNoPendingDependencies(parentQueueKey, parentDependenciesKey, parentKey, parentId, timestamp)
end
```

The problem is: when multiple child jobs complete almost simultaneously, the following race condition may occur:

```
Time T1: Job A completes, enters moveToFinished
Time T2: Job A's moveToFinished writes result to processed set
Time T3: Job B completes, enters moveToFinished  
Time T4: Job B's moveToFinished also triggers updateParentDepsIfNeeded
Time T5: Both scripts detect SCARD == 0
Time T6: Both scripts call moveParentToWait, causing parent job to be added twice!
```

## 5. Fourth Bug: Incomplete Job Deletion Causes Re-execution

### 5.1 Problem Location

**File**: `includes/removeJobWithChildren.lua` and `includes/removeJobFromAnyState.lua`

### 5.2 Problem Description

```lua
local function removeJobWithChildren(prefix, jobId, parentKey, options)
    local jobKey = prefix .. jobId
    
    if options.ignoreLocked then
        if isLocked(prefix, jobId) then
            return  -- If job is locked, return directly without deleting
        end
    end
    ...
end
```

When `ignoreLocked` option is true and the job is currently locked (being processed by a worker), the delete operation returns directly, but the job remains in the active queue. This causes:
1. Job is not deleted
2. Worker continues processing this job that should have been cancelled
3. Even if the job is marked for deletion, it will be added to the completed queue after completion

## 6. Root Cause Analysis

### 6.1 Design Flaws

1. **Incomplete Lock Mechanism**: `prepareJobForProcessing` sets lock after job data update, creating a time window
2. **Non-atomic State Checks**: Multiple scripts' checks of job state are not fully atomic
3. **Incomplete Error Recovery Logic**: Some error scenarios lack proper rollback mechanisms

### 6.2 Insufficient Concurrency Control

When multiple workers or scripts operate on the same job simultaneously, there are insufficient mechanisms to ensure consistency.

## 7. Suggested Fix Solutions

### 7.1 Fix moveStalledJobsToWait

```lua
-- Add stricter verification when checking stalled jobs
if (rcall("EXISTS", jobKey .. ":lock") == 0) then
    local removed = rcall("LREM", activeKey, 1, jobId)
    if (removed > 0) then
        -- Only jobs successfully removed from active are truly stalled
        -- Continue processing...
    else
        -- Job is no longer in active, may have completed or been processed by another worker
        -- Remove from stalled set (if exists)
        rcall("SREM", stalledKey, jobId)
    end
end
```

### 7.2 Fix moveParentToFailedIfNeeded

Replace `moveParentToWait` call with logic to move parent job to failed state:

```lua
if rcall("ZSCORE", parentWaitingChildrenKey, parentId) then
    ...
    rcall("ZREM", parentWaitingChildrenOrDelayedKey, parentId)
    local deferredFailure = "child " .. jobIdKey .. " failed"
    rcall("HSET", parentKey, "defa", deferredFailure)
    -- Should not call moveParentToWait, but add to failed set
    rcall("ZADD", parentFailedKey, timestamp, parentId)
end
```

### 7.3 Fix updateParentDepsIfNeeded Race

Add atomic check before calling `moveParentToWaitIfNoPendingDependencies`:

```lua
-- Use WATCH/MULTI/EXEC to ensure atomicity
-- Or add additional existence check in Lua script
if rcall("ZREM", parentWaitingChildrenKey, parentId) == 1 then
    -- Only move if successfully removed
    moveParentToWait(...)
end
```

### 7.4 Fix Job Deletion Logic

For jobs that need to be deleted but are being processed:
1. Mark job as "pending deletion" state
2. When job completes, move directly to completed/failed queue then immediately delete
3. Instead of waiting for worker to complete before processing

## 8. Impact Scope

- **Security**: High - May cause task re-execution, leading to data inconsistency
- **Reliability**: High - Tasks that should fail may be incorrectly re-executed
- **Data Integrity**: High - Job state may become inconsistent