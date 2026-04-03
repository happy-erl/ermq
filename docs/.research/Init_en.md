# ERMQ Learning and Discovery Report

## 1. Project Overview

ERMQ is a Redis-based message queue system, an Erlang port of BullMQ (Node.js). It uses Lua scripts to ensure atomic operations.

## 2. System Architecture

### 2.1 Component Structure

```
ERMQ/
├── src/                    # Erlang source code
│   ├── ermq.erl           # Main module (empty)
│   ├── ermq_job.erl       # Job management
│   ├── ermq_redis.erl     # Redis connection wrapper
│   ├── ermq_scripts.erl   # Lua script manager
│   ├── ermq_config.erl    # Configuration management
│   ├── ermq_utils.erl     # Utility functions
│   ├── ermq_msgpack.erl   # MessagePack encoder
│   └── ermq_errors.erl    # Error definitions
├── priv/lua/              # Lua scripts
│   ├── includes/          # Reusable Lua functions
│   └── *.lua              # Main Lua scripts
└── test/                  # Test files
```

### 2.2 Core Module Description

#### ermq_job.erl
- Responsible for job creation, addition, and retrieval
- Adds jobs to Redis via Lua scripts
- Supports standard jobs, delayed jobs, and priority jobs

#### ermq_redis.erl
- Uses `eredis` library for Redis communication
- Provides `command/2` and `pipeline/2` interfaces
- Supports aliases `q/2` and `qp/2`

#### ermq_scripts.erl
- Manages Lua script loading and caching
- Uses ETS table to cache script SHA1
- Supports `@include` directive
- Automatically handles NOSCRIPT errors and retries

#### ermq_msgpack.erl
- Self-implemented MessagePack encoder
- Used to pass complex parameters between Lua scripts
- Supports integers, floats, binaries, atoms, lists, and maps

## 3. Job Status and Flow

### 3.1 Job Status

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

### 3.2 Key Flows

#### Job Addition (addStandardJob/addDelayedJob/addPrioritizedJob)
1. Store job data in `{prefix}:{jobId}` key
2. Place job ID into corresponding queue (wait/delayed/prioritized)
3. Emit event in event stream

#### Job Processing (moveToActive)
1. First check if there are delayed jobs that can be promoted to wait queue
2. Check rate limiting
3. Check if queue is paused or at capacity
4. Move from wait queue to active queue
5. Set lock
6. Return job data

#### Job Completion (moveToFinished)
1. Verify job exists
2. Remove lock
3. Remove from active queue
4. Handle parent-child job dependencies
5. Add to completed/failed set
6. Emit event
7. Optionally get next job

#### Job Retry (retryJob)
1. Remove from active queue
2. Add to wait queue (considering priority)
3. Emit waiting event

#### Stalled Job Recovery (moveStalledJobsToWait)
1. Check all jobs in stalled set
2. For jobs without lock, move back to wait queue
3. Mark jobs in active queue as possibly stalled

## 4. Lua Includes Analysis

### 4.1 Core Functions

#### prepareJobForProcessing
- Sets rate limiting counter
- Sets job lock (if token != "0")
- Updates processedOn and attempt count
- Returns job data

#### removeJobFromAnyState
- Removes job from any state set
- Checks in order: completed, waiting-children, delayed, failed, prioritized, wait, paused, active

#### moveParentToWaitIfNeeded/IfNoPendingDependencies
- When child job completes, checks if parent job can be moved to wait queue
- Handles cross-queue parent-child relationships

### 4.2 Job Removal

#### removeJobWithChildren
- Recursively removes job and its child jobs
- Supports ignoreProcessed and ignoreLocked options

#### removeParentDependencyKey
- Removes child job's dependency on parent job
- If all dependencies complete, moves parent job to wait queue

## 5. Data Structures

### 5.1 Redis Key Structure

```
{prefix}:{queueName}
├── wait           - Waiting queue (LIST)
├── active         - Active queue (LIST)
├── paused         - Paused queue (LIST)
├── delayed        - Delayed jobs (ZSET)
├── prioritized    - Priority jobs (ZSET)
├── completed      - Completed jobs (ZSET)
├── failed         - Failed jobs (ZSET)
├── waiting-children - Waiting for children (ZSET)
├── stalled        - Stalled jobs (SET)
├── meta           - Queue metadata (HASH)
├── events         - Event stream (STREAM)
├── events:opts    - Event options
├── marker         - Marker key
├── id             - Job ID counter
├── {jobId}        - Job data (HASH)
│   ├── data       - Job data (JSON)
│   ├── opts       - Job options (JSON)
│   ├── priority   - Priority
│   ├── delay      - Delay time
│   ├── attempts   - Max attempts
│   ├── atm        - Attempted count
│   ├── stc        - Stalled count
│   ├── processedOn - Processing time
│   ├── finishedOn  - Completion time
│   ├── defa       - Failure reason
│   ├── returnvalue - Return value
│   ├── parentKey   - Parent job key
│   ├── parent      - Parent job info (JSON)
│   ├── deid        - Deduplication ID
│   ├── {jobId}:lock - Job lock
│   ├── {jobId}:dependencies - Dependencies (SET)
│   ├── {jobId}:processed - Processing results (HASH)
│   ├── {jobId}:failed - Failure results (HASH)
│   └── {jobId}:unsuccessful - Unsuccessful records (ZSET)
```

## 6. Configuration

### 6.1 Queue Options
```erlang
#{
    prefix => <<"ermq">>,        % Redis key prefix
    connection => #{},            % Redis connection config
    defaultJobOptions => #{}      % Default job options
}
```

### 6.2 Job Options
```erlang
#{
    attempts => 1,                % Max attempts
    delay => 0,                   % Delay time (milliseconds)
    timestamp => os:system_time(millisecond),  % Timestamp
    priority => undefined,        % Priority
    jobId => undefined            % Custom job ID
}
```

## 7. Test Findings

### 7.1 Known Issues
Running tests revealed 4 failures:
1. `test_job_retrieval` - not_found error
2. `test_add_delayed_job` - WRONGTYPE error
3. `test_add_prioritized_job` - WRONGTYPE error
4. `test_update_progress` - value mismatch

These failures may be related to Redis data state, residual data may cause type errors.

## 8. Potential Issues Summary

### 8.1 Race Conditions
- `moveStalledJobsToWait` may have race between checking lock and moving job
- Time window may exist between job deletion and status update

### 8.2 Logic Issues
- Handling of child jobs in `moveToFinished` may cause parent job to be reactivated
- `removeJobWithChildren` may cause performance issues when handling large numbers of child jobs

### 8.3 Edge Cases
- Handling of empty lists and non-existent keys is not fully consistent
- Error handling when jobs don't exist in some scripts is not comprehensive enough