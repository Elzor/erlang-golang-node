-module(go_controller).

-behaviour(gen_server).

-author('Maxim Molchanov <elzor.job@gmail.com>').

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

%% includes
-include_lib("eunit/include/eunit.hrl").
-include_lib("common/include/log.hrl").

%% defines

%% records
-record(state, {
        port_ref :: port(),
        remote_pid = undefined :: pid()
        }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(_Options) ->
    process_flag(trap_exit, true),
    PortRef = start_go_node(),
    erlang:send_after(75, self(), {'$gen_cast', ping_pong_with_go}),
    {ok, #state{ port_ref = PortRef }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(Msg, _From, State) ->
    ?ERR("unhandled call message: ~p", [Msg]),
    {reply, unimplemented, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(ping_pong_with_go, State) ->
    {ok, GoMBox} = application:get_env(gonode, go_mailbox),
    gen_server:cast(GoMBox, {ping, self()}),
    {noreply, State};

handle_cast(Msg, State) ->
    ?ERR("unhandled cast message: ~p", [Msg]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------

handle_info({pong, Pid}, #state{remote_pid = undefined} = State) ->
    ?LOG("connection to node established, pid ~p", [Pid]),
    % TODO: do it when goerlang will support
    %link(Pid),
    {noreply, State#state{remote_pid = Pid}};

handle_info({pong, _}, State) ->
    {noreply, State};

handle_info({Port, {exit_status, Status}}, #state{port_ref = Port} = State) ->
    ?ERR("external app exited with status ~p", [Status]),
    {stop, {error, {app_exit, Status}}, State};

handle_info({'EXIT', _Pid, Reason}, State) ->
    ?ERR("external mbox exited with reason ~p", [Reason]),
    {stop, {error, {mbox_exit, Reason}}, State};

handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_, #state{remote_pid = Pid}) when is_pid(Pid) ->
    {ok, GoMBox} = application:get_env(gonode, go_mailbox),
    gen_server:cast(GoMBox, stop),
    ok;
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
start_go_node() ->
    {ok, GoCmd}         = application:get_env(gonode, go_cmd),
    {ok, GoEpmdPort}    = application:get_env(gonode, go_epmd_port),
    {ok, GoMBox}        = application:get_env(gonode, go_mailbox),
    {GenName, NodeName} = GoMBox,
    {ok, GoLogFile}     = application:get_env(gonode, go_log_file),
    {ok, GoPidFile}     = application:get_env(gonode, go_pid_file),
    CmdPath             = code:lib_dir(gonode, priv),
    Cmd = lists:flatten([
                CmdPath, "/", GoCmd,
                " -epmd_port "  , integer_to_list(GoEpmdPort),
                " -log "        , CmdPath, "/", GoLogFile,
                " -gen_server " , atom_to_list(GenName),
                " -name "       , atom_to_list(NodeName),
                " -cookie "     , atom_to_list(erlang:get_cookie()),
                " -pid_file "   , CmdPath, "/", GoPidFile ]),
    ?LOG("Start Go node with command: ~p", [Cmd]),
    force_kill_process(),
    open_port({spawn, Cmd},[exit_status]).

force_kill_process() ->
    {ok, GoPidFile} = application:get_env(gonode, go_pid_file),
    CmdPath         = code:lib_dir(gonode, priv),
    Cmd             = lists:flatten(["kill -9 $(cat ", CmdPath, "/", GoPidFile, ")"]),
    os:cmd(Cmd),
    os:cmd("pkill xgn."),
    ok.
