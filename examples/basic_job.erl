%%%-------------------------------------------------------------------
%%% Basic Job Example
%%% Demonstrates how to create and process a basic job.
%%%-------------------------------------------------------------------
-module(basic_job).

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
    
    %% 5. Add a basic job
    io:format("~n=== Adding a basic job ===~n"),
    Data = #{<<"message">> => <<"Hello, World!">>, <<"timestamp">> => erlang:system_time(millisecond)},
    {ok, JobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"basic-job">>, Data),
    io:format("Job created with ID: ~s~n", [JobId]),
    
    %% 6. Retrieve the job
    io:format("~n=== Retrieving the job ===~n"),
    {ok, Job} = ermq_job:from_id(Client, <<"ermq">>, <<"test-queue">>, JobId),
    io:format("Job data: ~p~n", [maps:get(<<"data">>, Job)]),
    
    %% 7. Check queue status
    io:format("~n=== Checking queue status ===~n"),
    {ok, WaitCount} = ermq_redis:q(Client, ["LLEN", "ermq:test-queue:wait"]),
    io:format("Jobs in wait queue: ~s~n", [WaitCount]),
    
    %% 8. Clean up and close
    cleanup(Client),
    ermq_redis:stop(Client),
    
    io:format("~n=== Basic job example completed! ===~n"),
    ok.

cleanup(Client) ->
    {ok, Keys} = ermq_redis:q(Client, ["KEYS", "ermq:test-queue:*"]),
    lists:foreach(fun(Key) -> ermq_redis:q(Client, ["DEL", Key]) end, Keys).