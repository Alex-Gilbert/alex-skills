-module(alex_memory_ffi).
-export([get_today/0, put_author/1, get_author/0]).

get_today() ->
    {{Y, M, D}, _} = calendar:local_time(),
    list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).

put_author(Author) ->
    erlang:put(mcp_author, Author),
    nil.

get_author() ->
    case erlang:get(mcp_author) of
        undefined -> {error, nil};
        Author -> {ok, Author}
    end.
