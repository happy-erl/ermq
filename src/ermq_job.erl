%%%-------------------------------------------------------------------
%%% Job definition and manipulation module.
%%% Corresponds to src/classes/job.ts.
%%% Handles Job creation, adding to Redis via Lua scripts, and retrieval.
%%% Uses internal ermq_msgpack for Lua script arguments.
%%%-------------------------------------------------------------------
-module(ermq_job).

%% API
-export([add/5, add/6]).
-export([from_id/4]).
-export([update_progress/5]).

-include("ermq.hrl").

%%%===================================================================
%%% API Functions
%%%===================================================================

%% Adds a new job to the queue.
add(Client, Prefix, QueueName, Name, Data, Opts) ->
    JobOpts = maps:merge(?DEFAULT_JOB_OPTS, Opts),
    
    %% Generate ID if missing
    JobId = case maps:get(jobId, JobOpts, undefined) of
        undefined -> ermq_utils:v4();
        CustomId -> ermq_utils:to_binary(CustomId)
    end,
    
    Timestamp = maps:get(timestamp, JobOpts),
    Delay = maps:get(delay, JobOpts, 0),
    Priority = maps:get(priority, JobOpts, undefined),
    
    %% Prepare Data and Opts
    JsonData = ermq_utils:json_encode(Data),
    
    %% Use internal msgpack encoder
    PackedOpts = ermq_msgpack:pack(JobOpts),
    
    {ScriptName, Keys, Args} = prepare_add_script(
        Prefix, QueueName, JobId, Name, Timestamp, Delay, Priority, PackedOpts, JsonData
    ),
    
    case ermq_scripts:run(Client, ScriptName, Keys, Args) of
        {ok, _Result} -> {ok, JobId};
        Error -> Error
    end.

add(Client, Prefix, QueueName, Name, Data) ->
    add(Client, Prefix, QueueName, Name, Data, #{}).

%% Retrieves a Job from Redis by ID.
from_id(Client, Prefix, QueueName, JobId) ->
    JobKey = ermq_utils:to_key(Prefix, [QueueName, JobId]),
    case ermq_redis:q(Client, ["HGETALL", JobKey]) of
        {ok, []} -> {error, not_found};
        {ok, ListData} ->
            MapData = list_to_map(ListData),
            RawData = maps:get(<<"data">>, MapData, <<>>),
            RawOpts = maps:get(<<"opts">>, MapData, <<>>),
            RawReturn = maps:get(<<"returnvalue">>, MapData, <<>>),
            
            %% Decode JSON fields
            Job = MapData#{
                <<"data">> => safe_json_decode(RawData),
                <<"opts">> => safe_json_decode(RawOpts),
                <<"returnvalue">> => safe_json_decode(RawReturn),
                id => JobId
            },
            {ok, Job};
        Error -> Error
    end.

%% Updates job progress.
update_progress(Client, Prefix, QueueName, JobId, Progress) ->
    JsonProgress = ermq_utils:json_encode(Progress),
    Keys = [
        ermq_utils:to_key(Prefix, [QueueName, JobId]),
        ermq_utils:to_key(Prefix, [QueueName, "events"]),
        ermq_utils:to_key(Prefix, [QueueName, "meta"])
    ],
    Args = [ermq_utils:to_binary(JobId), JsonProgress],
    ermq_scripts:run(Client, 'updateProgress-3', Keys, Args).

%%%===================================================================
%%% Internal Functions
%%%===================================================================

prepare_add_script(Prefix, QueueName, JobId, Name, Timestamp, Delay, Priority, PackedOpts, JsonData) ->
    %% Redis Keys (Standard 9 keys for BullMQ v4/v5) with queue name
    WaitKey = ermq_utils:to_key(Prefix, [QueueName, <<"wait">>]),
    PausedKey = ermq_utils:to_key(Prefix, [QueueName, <<"paused">>]),
    MetaKey = ermq_utils:to_key(Prefix, [QueueName, <<"meta">>]),
    IdKey = ermq_utils:to_key(Prefix, [QueueName, <<"id">>]),
    CompletedKey = ermq_utils:to_key(Prefix, [QueueName, <<"completed">>]),
    DelayedKey = ermq_utils:to_key(Prefix, [QueueName, <<"delayed">>]),
    ActiveKey = ermq_utils:to_key(Prefix, [QueueName, <<"active">>]),
    EventsKey = ermq_utils:to_key(Prefix, [QueueName, <<"events">>]),
    MarkerKey = ermq_utils:to_key(Prefix, [QueueName, <<"marker">>]),
    PrioritizedKey = ermq_utils:to_key(Prefix, [QueueName, <<"prioritized">>]),
    PriorityCounterKey = ermq_utils:to_key(Prefix, [QueueName, <<"pc">>]),
    
    %% MsgPack Arguments Construction
    %% Use 'nil' which ermq_msgpack converts to 0xC0
    PrefixWithColon = <<Prefix/binary, ":", QueueName/binary, ":">>,
    ArgList = [
        PrefixWithColon,
        JobId,
        Name,
        Timestamp,
        nil, %% parentKey
        nil, %% parentDependenciesKey
        nil, %% parent
        nil, %% repeatJobKey
        nil  %% deduplicationKey
    ],
    
    PackedArgs = ermq_msgpack:pack(ArgList),
    
    %% Final Args to Redis: [PackedArgs, JsonData, PackedOpts]
    FinalArgs = [PackedArgs, JsonData, PackedOpts],

    if
        Delay > 0 ->
            %% addDelayedJob-6 expects keys: marker, meta, id, delayed, completed, events
            Keys = [MarkerKey, MetaKey, IdKey, DelayedKey, CompletedKey, EventsKey],
            {'addDelayedJob-6', Keys, FinalArgs ++ [ermq_utils:to_binary(Delay)]};

        Priority =/= undefined ->
            %% addPrioritizedJob-9 expects keys: marker, meta, id, prioritized, delayed, completed, active, events, pc
            Keys = [MarkerKey, MetaKey, IdKey, PrioritizedKey, DelayedKey, 
                    CompletedKey, ActiveKey, EventsKey, PriorityCounterKey],
            {'addPrioritizedJob-9', Keys, FinalArgs ++ [ermq_utils:to_binary(Priority)]};

        true ->
            %% addStandardJob-9 expects keys: wait, paused, meta, id, completed, delayed, active, events, marker
            Keys = [WaitKey, PausedKey, MetaKey, IdKey, 
                    CompletedKey, DelayedKey, ActiveKey, EventsKey, MarkerKey],
            {'addStandardJob-9', Keys, FinalArgs}
    end.

list_to_map(List) -> list_to_map(List, #{}).
list_to_map([], Acc) -> Acc;
list_to_map([K, V | T], Acc) -> list_to_map(T, maps:put(K, V, Acc)).

safe_json_decode(<<>>) -> #{};
safe_json_decode(null) -> #{};
safe_json_decode(Bin) ->
    try ermq_utils:json_decode(Bin)
    catch _:_ -> Bin
    end.