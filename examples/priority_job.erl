%%%-------------------------------------------------------------------
%%% Priority Job Example
%%% Demonstrates how to create jobs with different priorities.
%%% Higher priority jobs are processed before lower priority ones.
%%%-------------------------------------------------------------------
-module(priority_job).

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
    
    %% 5. Add jobs with different priorities
    io:format("~n=== Adding jobs with different priorities ===~n"),
    
    %% Low priority job (priority = 3)
    LowData = #{<<"task">> => <<"low-priority-task">>, <<"priority">> => <<"low">>},
    LowOpts = #{priority => 3},
    {ok, LowJobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"low-priority">>, LowData, LowOpts),
    io:format("Low priority job created with ID: ~s~n", [LowJobId]),
    
    %% High priority job (priority = 1)
    HighData = #{<<"task">> => <<"high-priority-task">>, <<"priority">> => <<"high">>},
    HighOpts = #{priority => 1},
    {ok, HighJobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"high-priority">>, HighData, HighOpts),
    io:format("High priority job created with ID: ~s~n", [HighJobId]),
    
    %% Medium priority job (priority = 2)
    MedData = #{<<"task">> => <<"medium-priority-task">>, <<"priority">> => <<"medium">>},
    MedOpts = #{priority => 2},
    {ok, MedJobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"medium-priority">>, MedData, MedOpts),
    io:format("Medium priority job created with ID: ~s~n", [MedJobId]),
    
    %% 6. Check prioritized queue
    io:format("~n=== Checking prioritized queue ===~n"),
    {ok, PrioCount} = ermq_redis:q(Client, ["ZCARD", "ermq:test-queue:prioritized"]),
    io:format("Jobs in prioritized queue: ~s~n", [PrioCount]),
    
    %% 7. Get priority scores for each job
    io:format("~n=== Priority scores (lower = higher priority) ===~n"),
    {ok, HighScore} = ermq_redis:q(Client, ["ZSCORE", "ermq:test-queue:prioritized", HighJobId]),
    {ok, MedScore} = ermq_redis:q(Client, ["ZSCORE", "ermq:test-queue:prioritized", MedJobId]),
    {ok, LowScore} = ermq_redis:q(Client, ["ZSCORE", "ermq:test-queue:prioritized", LowJobId]),
    io:format("High priority job score: ~s~n", [HighScore]),
    io:format("Medium priority job score: ~s~n", [MedScore]),
    io:format("Low priority job score: ~s~n", [LowScore]),
    
    %% 8. Clean up and close
    cleanup(Client),
    ermq_redis:stop(Client),
    
    io:format("~n=== Priority job example completed! ===~n"),
    io:format("Note: Jobs with lower scores are processed first.~n"),
    ok.

cleanup(Client) ->
    {ok, Keys} = ermq_redis:q(Client, ["KEYS", "ermq:test-queue:*"]),
    lists:foreach(fun(Key) -> ermq_redis:q(Client, ["DEL", Key]) end, Keys).