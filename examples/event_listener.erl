%%%-------------------------------------------------------------------
%%% Event Listener Example
%%% Demonstrates how to listen to job events using Redis Streams.
%%%-------------------------------------------------------------------
-module(event_listener).

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
    
    %% 5. Start event listener in a separate process
    io:format("~n=== Starting event listener ===~n"),
    ListenerPid = spawn(fun() -> listen_events(Client) end),
    
    %% 6. Add some jobs to generate events
    io:format("~n=== Adding jobs to generate events ===~n"),
    
    timer:sleep(100),  % Give listener time to start
    
    {ok, JobId1} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"job-1">>, #{<<"data">> => <<"first">>}),
    io:format("Created job 1: ~s~n", [JobId1]),
    
    timer:sleep(200),
    
    {ok, JobId2} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"job-2">>, #{<<"data">> => <<"second">>}, #{priority => 1}),
    io:format("Created job 2: ~s~n", [JobId2]),
    
    timer:sleep(200),
    
    {ok, JobId3} = ermq_job:add(Client, <<"ermq">>, <<"test-queue">>, <<"job-3">>, #{<<"data">> => <<"third">>}, #{delay => 1000}),
    io:format("Created job 3: ~s~n", [JobId3]),
    
    %% 7. Wait for events to be processed
    timer:sleep(1000),
    
    %% 8. Stop listener
    io:format("~n=== Stopping event listener ===~n"),
    ListenerPid ! stop,
    
    %% 9. Check events stream
    io:format("~n=== Checking events stream ===~n"),
    {ok, EventCount} = ermq_redis:q(Client, ["XLEN", "ermq:test-queue:events"]),
    io:format("Total events in stream: ~s~n", [EventCount]),
    
    %% 10. Clean up and close
    cleanup(Client),
    ermq_redis:stop(Client),
    
    io:format("~n=== Event listener example completed! ===~n"),
    ok.

listen_events(Client) ->
    %% Read events from the stream
    case ermq_redis:q(Client, ["XREAD", "COUNT", "10", "BLOCK", "500", "STREAMS", "ermq:test-queue:events", "0"]) of
        {ok, undefined} ->
            %% Timeout, continue listening
            listen_events(Client);
        {ok, Events} ->
            %% Process events
            lists:foreach(fun([_Stream, EventList]) ->
                lists:foreach(fun([Id, Fields]) ->
                    io:format("~nEvent ID: ~s~n", [Id]),
                    print_fields(Fields)
                end, EventList)
            end, Events),
            listen_events(Client);
        {error, _} ->
            %% Error or stopped
            ok
    end.

print_fields([]) -> ok;
print_fields([Field, Value | Rest]) ->
    io:format("  ~s: ~s~n", [Field, Value]),
    print_fields(Rest).

cleanup(Client) ->
    {ok, Keys} = ermq_redis:q(Client, ["KEYS", "ermq:test-queue:*"]),
    lists:foreach(fun(Key) -> ermq_redis:q(Client, ["DEL", Key]) end, Keys).