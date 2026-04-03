%%%-------------------------------------------------------------------
%%% Progress Update Example
%%% Demonstrates how to update and track job progress.
%%%-------------------------------------------------------------------
-module(progress_update).

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
    
    %% 5. Add a job
    io:format("~n=== Adding a job for progress tracking ===~n"),
    Data = #{<<"task">> => <<"long-running-task">>, <<"steps">> => 5},
    {ok, JobId} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"progress-job">>, Data),
    io:format("Job created with ID: ~s~n", [JobId]),
    
    %% 6. Update progress at different stages
    io:format("~n=== Updating progress ===~n"),
    
    io:format("Updating progress to 20%...~n"),
    {ok, _} = ermq_job:update_progress(Client, <<"ermq">>, <<"test-queue">>, JobId, 20),
    
    io:format("Updating progress to 50%...~n"),
    {ok, _} = ermq_job:update_progress(Client, <<"ermq">>, <<"test-queue">>, JobId, 50),
    
    io:format("Updating progress to 80%...~n"),
    {ok, _} = ermq_job:update_progress(Client, <<"ermq">>, <<"test-queue">>, JobId, 80),
    
    io:format("Updating progress to 100%...~n"),
    {ok, _} = ermq_job:update_progress(Client, <<"ermq">>, <<"test-queue">>, JobId, 100),
    
    %% 7. Retrieve the job and check progress
    io:format("~n=== Retrieving job to verify progress ===~n"),
    {ok, Job} = ermq_job:from_id(Client, <<"ermq">>, <<"test-queue">>, JobId),
    io:format("Job data: ~p~n", [maps:get(<<"data">>, Job)]),
    
    %% 8. Check raw progress value from Redis
    io:format("~n=== Checking raw progress value ===~n"),
    {ok, ProgressVal} = ermq_redis:q(Client, ["HGET", "ermq:test-queue:" ++ binary_to_list(JobId), "progress"]),
    io:format("Progress value in Redis: ~s~n", [ProgressVal]),
    
    %% 9. Clean up and close
    cleanup(Client),
    ermq_redis:stop(Client),
    
    io:format("~n=== Progress update example completed! ===~n"),
    ok.

cleanup(Client) ->
    {ok, Keys} = ermq_redis:q(Client, ["KEYS", "ermq:test-queue:*"]),
    lists:foreach(fun(Key) -> ermq_redis:q(Client, ["DEL", Key]) end, Keys).