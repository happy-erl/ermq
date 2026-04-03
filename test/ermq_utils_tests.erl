-module(ermq_utils_tests).
-include_lib("eunit/include/eunit.hrl").

%% Test UUID generation format
uuid_test() ->
    UUID = ermq_utils:v4(),
    %% Check if it's binary
    ?assert(is_binary(UUID)),
    %% UUID standard length is 36
    ?assertEqual(36, byte_size(UUID)),
    %% Simple check if there are hyphens in the middle
    ?assertEqual($-, binary:at(UUID, 8)),
    ?assertEqual($-, binary:at(UUID, 13)).

%% Test Redis Key concatenation
to_key_test() ->
    Prefix = <<"bull">>,
    %% Test single part concatenation
    ?assertEqual(<<"bull:myqueue">>, ermq_utils:to_key(Prefix, "myqueue")),
    %% Test multiple parts concatenation
    ?assertEqual(<<"bull:myqueue:123">>, ermq_utils:to_key(Prefix, ["myqueue", 123])),
    %% Test concatenation with binary
    ?assertEqual(<<"bull:test:job">>, ermq_utils:to_key(Prefix, [<<"test">>, "job"])).

%% Test JSON encoding and decoding
json_test() ->
    Map = #{<<"key">> => <<"value">>, <<"num">> => 123},
    Encoded = ermq_utils:json_encode(Map),
    ?assert(is_binary(Encoded)),
    
    Decoded = ermq_utils:json_decode(Encoded),
    ?assertEqual(Map, Decoded).

%% Test empty value check
is_empty_test() ->
    ?assert(ermq_utils:is_empty(undefined)),
    ?assert(ermq_utils:is_empty(null)),
    ?assert(ermq_utils:is_empty([])),
    ?assert(ermq_utils:is_empty(<<>>)),
    ?assertNot(ermq_utils:is_empty(0)),
    ?assertNot(ermq_utils:is_empty(<<"a">>)).
