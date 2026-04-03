-module(ermq_config_tests).
-include_lib("eunit/include/eunit.hrl").
-include_lib("ermq/include/ermq.hrl").

%% Test default value merging for queue configuration
new_queue_opts_test() ->
    %% Case 1: Empty configuration
    Opts = ermq_config:new_queue_opts(#{}),
    ?assertEqual(?DEFAULT_PREFIX, maps:get(prefix, Opts)),
    ?assertEqual(#{}, maps:get(connection, Opts)),
    
    %% Case 2: User-defined configuration
    UserOpts = #{prefix => <<"my-queue">>, connection => #{host => "redis"}},
    Merged = ermq_config:new_queue_opts(UserOpts),
    ?assertEqual(<<"my-queue">>, maps:get(prefix, Merged)),
    ?assertEqual("redis", maps:get(host, maps:get(connection, Merged))).

%% Test default value merging for Worker configuration
new_worker_opts_test() ->
    Opts = ermq_config:new_worker_opts(#{}),
    %% Verify concurrency default value is 1
    ?assertEqual(1, maps:get(concurrency, Opts)),
    %% Verify lock duration
    ?assertEqual(30000, maps:get(lockDuration, Opts)).

%% Test extracting eredis parameters from configuration
get_redis_opts_test() ->
    %% Default case
    {Host, Port, DB, _Pass} = ermq_config:get_redis_opts(#{}), %% Use _Pass to ignore
    ?assertEqual("127.0.0.1", Host),
    ?assertEqual(6379, Port),
    ?assertEqual(0, DB),
    
    %% Custom case
    Config = #{connection => #{host => "192.168.1.1", port => 9999, db => 2, password => "secret"}},
    {Host2, Port2, DB2, Pass2} = ermq_config:get_redis_opts(Config),
    ?assertEqual("192.168.1.1", Host2),
    ?assertEqual(9999, Port2),
    ?assertEqual(2, DB2),
    ?assertEqual("secret", Pass2).
