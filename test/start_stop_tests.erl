-module(start_stop_tests).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common/include/test.hrl").

-define(APPS, [ sasl ]).

setup()->
    error_logger:tty(false),
    make_distrib("test_node", shortnames),
    ?START_APPS(
        ?APPS, [
            {sasl, [ {sasl_error_logger, {file, "test.log"}} ]}
            ]
        ),
    ok.

cleanup(_)->
    ?STOP_APPS(?APPS),
    stop_distrib(),
    error_logger:tty(true),
    ok.

main_test_()->
    ?FIXTURE(
        fun()->
            ?assertEqual(ok, application:load(gonode)),
            ?assertEqual(ok, application:set_env(gonode, go_mailbox, {go_srv, 'gonode@localhost'})),
            ?assertEqual(ok, application:start(gonode)),
            timer:sleep(150),
            ?debugVal(nodes()),
            ?assertEqual(
                {error,{already_started, gonode}},
                application:start(gonode)
                ),
            ?assertEqual(ok, application:stop(gonode)),
            ok
        end
        ).
        
        
-spec make_distrib( NodeName::string()|atom(), NodeType::shortnames | longnames) ->
   {ok, ActualNodeName::atom} | {error, Reason::term()}.
make_distrib(NodeName, NodeType) when is_list(NodeName) ->
   make_distrib(erlang:list_to_atom(NodeName), NodeType);
make_distrib(NodeName, NodeType) ->
        case node() of
            'nonode@nohost' -> 
                [] = os:cmd("epmd -daemon"),
                case net_kernel:start([NodeName, NodeType]) of 
                    {ok, _Pid} -> node() 
                end;
            CurrNode -> CurrNode
        end.

stop_distrib()->
        net_kernel:stop().
