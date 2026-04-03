# ermq

A robust message queue library for Erlang/OTP, inspired by [BullMQ](https://bullmq.io/) and built on top of Redis.

[![Apache 2.0 License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Erlang/OTP](https://img.shields.io/badge/Erlang%20OTP-26+-green.svg)](https://www.erlang.org/)

## Features

- **Job Management**: Create, process, and monitor background jobs
- **Delayed Jobs**: Schedule jobs to run after a specified delay
- **Priority Queues**: Assign priorities to jobs for ordered processing
- **Progress Tracking**: Update and monitor job progress
- **Event System**: Real-time events using Redis Streams
- **Redis-backed**: Built on Redis for reliability and scalability
- **Lua Scripts**: Atomic operations through embedded Lua scripts
- **Erlang/OTP Integration**: Leverages OTP principles for robustness

## Inspiration

This project draws inspiration from [BullMQ](https://bullmq.io/), a powerful Redis-based queue system for Node.js. We've adapted BullMQ's core concepts and design patterns to the Erlang/OTP ecosystem, providing similar functionality with Erlang's concurrency model and fault-tolerance features.

## Prerequisites

- **Erlang/OTP 26+**: [Download Erlang](https://www.erlang.org/downloads)
- **Redis 6+**: [Install Redis](https://redis.io/download)
- **rebar3**: [Install rebar3](https://rebar3.org/)

## Installation

### Using rebar3

Add `ermq` to your project's dependencies in `rebar.config`:

```erlang
{deps, [
    {ermq, "0.1.0", {git, "https://github.com/UGOtang/ermq.git", {branch, "main"}}}
]}.
```

Then fetch and compile:

```bash
rebar3 get-deps
rebar3 compile
```

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/UGOtang/ermq.git
   cd ermq
   ```

2. Compile the project:
   ```bash
   rebar3 compile
   ```

## Quick Start

### 1. Start Redis

Make sure Redis is running on localhost:6379 (default configuration):

```bash
redis-server
```

### 2. Basic Usage

```erlang
%% Start the Erlang shell
rebar3 shell

%% Initialize the script cache
ermq_scripts:init().

%% Connect to Redis
{ok, Client} = ermq_redis:start_link(#{}).

%% Add a job to the queue
Data = #{<<"message">> => <<"Hello, World!">>},
{ok, JobId} = ermq_job:add(Client, <<"ermq">>, <<"my-queue">>, <<"my-job">>, Data).

%% Retrieve the job
{ok, Job} = ermq_job:from_id(Client, <<"ermq">>, <<"my-queue">>, JobId).

%% Clean up (optional)
ermq_redis:stop(Client).
```

## Examples

The `examples/` directory contains runnable demonstrations of ermq's features:

### Basic Job
```erlang
basic_job:run().
```
Demonstrates creating and retrieving a basic job.

### Delayed Job
```erlang
delayed_job:run().
```
Shows how to schedule jobs with a 5-second delay.

### Priority Job
```erlang
priority_job:run().
```
Demonstrates creating jobs with different priorities (high, medium, low).

### Progress Update
```erlang
progress_update:run().
```
Shows how to update and track job progress from 0% to 100%.

### Event Listener
```erlang
event_listener:run().
```
Demonstrates listening to job events using Redis Streams.

For detailed information about the examples, see [examples/README.md](examples/README.md).

## Configuration

ermq can be configured through application environment variables or by passing options to the Redis client:

```erlang
%% In sys.config or app configuration
{ermq, [
    {redis_host, "localhost"},
    {redis_port, 6379},
    {redis_database, 0}
]}.

%% Or when starting the client
{ok, Client} = ermq_redis:start_link(#{
    host => "localhost",
    port => 6379,
    database => 0
}).
```

## Redis Key Structure

ermq uses a structured key format for organizing data in Redis:

```
ermq:<queue-name>:<type>
```

Common key patterns:
- `ermq:<queue>:wait` - List of waiting jobs
- `ermq:<queue>:delayed` - Sorted set of delayed jobs
- `ermq:<queue>:prioritized` - Sorted set of prioritized jobs
- `ermq:<queue>:events` - Redis Stream for events
- `ermq:<queue>:<job-id>` - Hash containing job data

## Development

### Running Tests

```bash
rebar3 eunit
```

### Building Documentation

```bash
rebar3 as docs edoc
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- [BullMQ](https://bullmq.io/) - The inspiration for this project's design and features
- [eredis](https://github.com/wooga/eredis) - Erlang Redis client used for communication
- [jsone](https://github.com/sile/jsone) - JSON encoding/decoding library

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Copyright

Copyright 2025, UGOtang <tangqihangzhang@163.com>.