%%%-------------------------------------------------------------------
%%% Delayed Job Example
%%% Demonstrates how to create a job with a delay before execution.
%%%-------------------------------------------------------------------
-module(delayed_job).

-export([run/0]).

run() ->
    %% 1. Start dependencies
    application:start(crypto),
    application:start(eredis),
    
    %% 2. Initialize script cache
    ermq_scripts:init(),
    
    %% 3. Connect to Redis
    {ok, Client} = ermq_redis:start_link(#{}),
    
    %% 4. Clean up any existing test data
    cleanup(Client),
    
    %% 5. Add a delayed job (5 seconds delay)
    io:format("~n=== Adding a delayed job (5 seconds) ===~n"),
    Data = #{<<"task">> => <<"send-email">>, <<"to">> => <<"user@example.com">>},
    Opts = #{delay => 5000},  % 5000 milliseconds = 5 seconds
    {ok, JobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"delayed-job">>, Data, Opts),
    io:format("Delayed job created with ID: ~s~n", [JobId]),
    
    %% 6. Check delayed queue
    io:format("~n=== Checking delayed queue ===~n"),
    {ok, DelayedCount} = ermq_redis:q(Client, ["ZCARD", "ermq:test-queue:delayed"]),
    io:format("Jobs in delayed queue: ~s~n", [DelayedCount]),
    
    %% 7. Get the job's delay score
    {ok, Score} = ermq_redis:q(Client, ["ZSCORE", "ermq:test-queue:delayed", JobId]),
    io:format("Job delay score (timestamp): ~s~n", [Score]),
    
    %% 8. Verify the job is not in wait queue yet
    {ok, WaitCount} = ermq_redis:q(Client, ["LLEN", "ermq:test-queue:wait"]),
    io:format("Jobs in wait queue: ~s (should be 0)~n", [WaitCount]),
    
    %% 9. Clean up and close
    cleanup(Client),
    ermq_redis:stop(Client),
    
    io:format("~n=== Delayed job example completed! ===~n"),
    io:format("Note: In a real scenario, the job would move to the wait queue after the delay.~n"),
    ok.

cleanup(Client) ->
    {ok, Keys} = ermq_redis:q(Client, ["KEYS", "ermq:test-queue:*"]),
    lists:foreach(fun(Key) -> ermq_redis:q(Client, ["DEL", Key]) end, Keys).