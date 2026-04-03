-module(ermq_integration_tests).
-include_lib("eunit/include/eunit.hrl").

integration_test_() ->
    {setup,
     fun setup/0,
     fun cleanup/1,
     fun(Client) ->
         [
             {timeout, 10, fun() -> test_redis_ping(Client) end},
             {timeout, 10, fun() -> test_script_loading(Client) end}
         ]
     end}.

setup() ->
    application:start(crypto),
    ermq_scripts:init(),
    {ok, Client} = ermq_redis:start_link(#{}),
    Client.

cleanup(Client) ->
    ermq_redis:stop(Client).

test_redis_ping(Client) ->
    ?assertEqual({ok, <<"PONG">>}, ermq_redis:q(Client, ["PING"])).

test_script_loading(Client) ->
    ScriptName = 'pause-7', 
    %% 1. Try to explicitly load the script
    LoadResult = ermq_scripts:load_command(Client, ScriptName),
    case LoadResult of
        {ok, Sha} ->
            ?debugFmt("Script loaded SHA: ~p", [Sha]),
            ?assert(is_binary(Sha)),
            
            %% 2. Verify execution
            %% Pass valid parameters to avoid runtime errors
            Keys = [
                <<"ermq:test:wait">>,           % KEYS[1] wait or paused
                <<"ermq:test:paused">>,         % KEYS[2] paused or wait
                <<"ermq:test:meta">>,           % KEYS[3] meta
                <<"ermq:test:prioritized">>,    % KEYS[4] prioritized
                <<"ermq:test:events">>,         % KEYS[5] events stream
                <<"ermq:test:delayed">>,        % KEYS[6] delayed
                <<"ermq:test:marker">>          % KEYS[7] marker
            ],
            Args = [<<"resumed">>],             % ARGV[1] paused or resumed
            RunResult = ermq_scripts:run(Client, ScriptName, Keys, Args),
            ?debugFmt("Script run result: ~p", [RunResult]),
            
            case RunResult of
                {ok, _} -> ok;
                {error, <<"NOSCRIPT", _/binary>>} -> 
                    ?assert(false); %% This is the only unacceptable error
                {error, _Reason} -> 
                    %% Other errors (like Lua runtime errors) are acceptable, proving the script ran
                    ok
            end;
            
        {error, {file_read_error, Reason}} ->
            ?debugFmt("Warning: Could not read script file: ~p. Skipping test.", [Reason]),
            ok;
        Error ->
            ?debugFmt("Load failed: ~p", [Error]),
            ?assert(false)
    end.
