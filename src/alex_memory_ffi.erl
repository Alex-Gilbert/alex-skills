-module(alex_memory_ffi).
-export([get_today/0]).

get_today() ->
    {{Y, M, D}, _} = calendar:local_time(),
    list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).
