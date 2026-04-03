# ermq Examples

This directory contains example Erlang modules demonstrating various features of the ermq message queue system.

## Prerequisites

1. Redis server running on localhost:6379 (default)
2. Erlang/OTP installed
3. ermq dependencies compiled

## Running the Examples

All examples can be run using the Erlang shell. First, compile the project:

```bash
cd /path/to/ermq
rebar3 compile
```

Then start the Erlang shell:

```bash
rebar3 shell
```

### 1. Basic Job Example

Demonstrates creating and retrieving a basic job:

```erlang
basic_job:run().
```

**What it does:**
- Connects to Redis
- Creates a simple job with data
- Retrieves the job by ID
- Shows queue status
- Cleans up test data

### 2. Delayed Job Example

Demonstrates creating a job with a delay before execution:

```erlang
delayed_job:run().
```

**What it does:**
- Creates a job with a 5-second delay
- Shows the job in the delayed queue (sorted set)
- Verifies the job is not in the wait queue yet
- Displays the delay score (timestamp)

### 3. Priority Job Example

Demonstrates creating jobs with different priorities:

```erlang
priority_job:run().
```

**What it does:**
- Creates three jobs with priorities 1 (high), 2 (medium), and 3 (low)
- Shows all jobs in the prioritized queue
- Displays priority scores (lower score = higher priority)
- Demonstrates how jobs are ordered by priority

### 4. Progress Update Example

Demonstrates updating and tracking job progress:

```erlang
progress_update:run().
```

**What it does:**
- Creates a job
- Updates progress from 0% to 100% in steps
- Retrieves the job to verify progress
- Shows the raw progress value stored in Redis

### 5. Event Listener Example

Demonstrates listening to job events using Redis Streams:

```erlang
event_listener:run().
```

**What it does:**
- Starts an event listener process
- Creates multiple jobs (normal, priority, delayed)
- Captures and displays events as they occur
- Shows the total number of events in the stream

## Redis Key Structure

After running examples, you can inspect Redis keys using `redis-cli`:

```bash
redis-cli
```

### Common Commands

```redis
# List all ermq keys
KEYS ermq:test-queue:*

# Check wait queue
LLEN ermq:test-queue:wait
LRANGE ermq:test-queue:wait 0 -1

# Check delayed queue
ZCARD ermq:test-queue:delayed
ZRANGE ermq:test-queue:delayed 0 -1 WITHSCORES

# Check prioritized queue
ZCARD ermq:test-queue:prioritized
ZRANGE ermq:test-queue:prioritized 0 -1 WITHSCORES

# Check events stream
XLEN ermq:test-queue:events
XRANGE ermq:test-queue:events - +

# View job data
HGETALL ermq:test-queue:<job-id>
```

## Cleanup

Each example automatically cleans up its test data. To manually clean up:

```redis
# Delete all test queue keys
DEL $(redis-cli KEYS 'ermq:test-queue:*')
```

## Notes

- Examples use the queue name `test-queue` to avoid conflicts
- Each example cleans up before and after execution
- Make sure Redis is running before executing examples
- The event listener example uses blocking reads with a 500ms timeout