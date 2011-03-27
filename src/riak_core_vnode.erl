%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc Riak Virtual Node behaviour.
%%
%% == Callbacks ==
%%
%% === Module:init([Index]) -> Result ===
%%
%% ```
%% Index = int() >= 0
%% Result = {ok, State}
%% State = term()
%% '''
%%
%% This function is called by the vnode process to build the initial
%% state.
%%
%% Index is the partition index assigned to this vnode.  The init
%% function must return `{ok, State}' where `State' is the internal
%% state of the vnode.
%%
%%
%% === Module:handle_command(Request, Sender, State) -> Result ===
%%
%% ```
%% Request = vnode_req()
%% Sender = sender()
%% State = NewState = term()
%% Result -> {reply, Reply, NewState}
%%           | {noreply, NewState}
%%           | {stop, Reason, NewState}
%% '''
%%
%% TODO Talk about return types and defined Reply and Reason types.
%%
%% This function is called by `riak_core_vnode' when it's been sent a
%% command to execute.  A command can be issued several ways:
%% `riak_core_vnode:send_command/2',
%% `riak_core_vnode:send_command_after/2' or even rely on the fact
%% that a vnode is a `gen_fsm' underneath and send via
%% `gen_fsm:send_event/2'.
%%
%% `Request' can be any term (typically a record) and represents an
%% action to be performed.
%%
%% `Sender' is a representation of where the request originated from
%% and can be used to send a reply.
%%
%% `State' is the internal state of the vnode.
%%
%%
%% === Module:handoff_starting(TargetNode, State) -> Result ===
%%
%% ```
%% TargetNode =
%% Result = {true, NewState} | {false, NewState}
%% State = NewState = term()
%% '''
%%
%% This function is called when if it is determined that this
%% particular vnode is not located on the proper physical node.  E.g.,
%% when a new node is added to the cluster and the vnodes must be
%% redistributed.
%%
%% As input it gets the `TargetNode' which is the node that the vnode
%% should be located on and state is the internal vnode state.
%%
%% This function should return `{true, NewState}' to indicate that
%% handoff should indeed occur or `{false, NewState}' to indicate that
%% handoff should be deferred for now.
%%
%%
%% === Module:handoff_cancelled(State) -> Result ===
%%
%% ```
%% State = NewState = term()
%% Result = {ok, NewState}
%% '''
%%
%% This function is called if it's determined that the max allowed
%% number of concurrent handoffs has already been reached.
%%
%% This function should return `{ok, NewState}' to indicate a
%% successful cancel.
%%
%%
%% === Module:handle_handoff_command(Request, Sender, State) -> Result ===
%%
%% ```
%% Request = vnode_req()
%% Sender = sender()
%% State = NewState = term()
%% Result = {reply, Reply, NewState}
%%        | {noreply, NewState}
%%        | {forward, NewState}
%%        | {drop, NewState}
%%        | {stop, Reason, NewState}
%% '''
%%
%% TODO Document.
%%
%%
%% === Module:handle_handoff_data(BinObj, State) -> Result ===
%%
%% ```
%% BinObj = binary()
%% State = NewState = term()
%% Result = {reply, ok, NewState}
%%        | {reply, {error, Error}, NewState}
%% '''
%%
%% This function is called when the vnode is given handoff data.  The
%% BinOjb is a binary and is the result of calling
%% `encode_handoff_item/2'.
%%
%% This function should return `{reply, ok, NewState}' if the handoff
%% was successful otherwise it should return `{reply, {error, Error},
%% NewState}' in the case of an error.
%%
%%
%% === Module:encode_handoff_item(K, V) -> Result ===
%%
%% ```
%% K = {Bucket, Key}
%% Bucket = riak_object:bucket()
%% Key = riak_object:key()
%% V = term()
%% Result -> binary()
%% '''
%%
%% This function is called by riak_core's handoff mechanism in order
%% to encode the data before it crosses the wire.
%%
%% N.B. This function works in conjunction with
%% `handle_handoff_data/2' and should encode the data in such a way
%% that `handle_handoff_data/2' can pull it apart.
%%
%%
%% === Module:handoff_finished(TargetNode, State) -> Result ===
%%
%% ```
%% TargetNode = node()
%% State = NewState = term()
%% Result = {ok, NewState}
%% '''
%%
%% This function is called when the vnode is finished handing-off it's
%% data to the `TargetNode'.
%%
%% This function should return `{ok, NewState}' to indicate it has
%% successfully finished.
%%
%%
%% === Module:is_empty(State) -> Result ===
%%
%% ```
%% State = NewState = term()
%% Result = {true, NewState} | {false, NewState}
%% '''
%%
%% When handoff is initiated the first thing the vnode does is
%% determine if there is anything to actually hand off.
%%
%% This function should return `{true, NewState}' if there is nothing
%% to hand off or `{false, NewState}' otherwise.
%%
%%
%% === Module:terminate(Reason, State) -> Result ===
%%
%% ```
%% Reason = normal | shutdown | {shutdown, term()} | term()
%% State = Result = term()
%% '''
%%
%% This function is called when the vnode is about to terminate.  The
%% `Reason' will depend on why it's being terminated, you can find out
%% more by reading the gen_fsm doc.
%%
%% The return value of this function is ignored.
%%
%%
%% === Module:delete(State) -> Result ===
%%
%% ```
%% State = NewState = term()
%% Result = {ok, NewState}
%% '''
%%
%% When handoff determines there is no more data to be transfered from
%% this node via `is_empty/1' it calls this function to delete the
%% vnode.  This allows the vnode to clean up after itself.
%%
%% This function should return `{ok, NewState}' to indicate a
%% successful delete.

-module(riak_core_vnode).


-behaviour(gen_fsm).
-include_lib("riak_core_vnode.hrl").
-export([behaviour_info/1]).
-export([start_link/2,
         start_link/3,
         send_command/2,
         send_command_after/2]).
-export([init/1, 
         active/2, 
         active/3, 
         handle_event/3,
         handle_sync_event/4, 
         handle_info/3, 
         terminate/3, 
         code_change/4]).
-export([reply/2]).
-export([get_mod_index/1]).

-spec behaviour_info(atom()) -> 'undefined' | [{atom(), arity()}].

%% @private
behaviour_info(callbacks) ->
    [{init,1},
     {handle_command,3},
     {handoff_starting,2},
     {handoff_cancelled,1},
     {handoff_finished,2},
     {handle_handoff_command,3},
     {handle_handoff_data,2},
     {encode_handoff_item,2},
     {is_empty,1},
     {terminate,2},
     {delete,1}];
behaviour_info(_Other) ->
    undefined.

%% handle_exit/4 is an optional behaviour callback that can be implemented. 
%% It will be called in the case that a process that is linked to the vnode
%% process dies and allows the module using the behaviour to take appropriate
%% action. It is called by handle_info when it receives an {'EXIT', Pid, Reason}
%% message and the function signature is: handle_exit(Pid, Reason, StateName, State).
%%
%% It should return a tuple indicating the next state for the fsm. For a list of
%% valid return types see the documentation for the gen_fsm handle_info callback.
%%
%% Here is what the spec for handle_exit/4 would look like:
%% -spec handle_exit(pid(), atom(), atom(), term()) ->
%%                          {next_state, atom(), term()} |
%%                          {next_state, atom(), term(), int() | infinity} |
%%                          {next_state, atom(), term(), hibernate} |
%%                          {stop, term(), term()}
                         

-define(DEFAULT_TIMEOUT, 60000).
-define(LOCK_RETRY_TIMEOUT, 10000).
-define(MODSTATE, State#state{mod=Mod,modstate=ModState}).
-record(state, {
          index :: partition(),
          mod :: module(),
          modstate :: term(),
          handoff_token :: non_neg_integer(),
          handoff_node=none :: none | node(),
          inactivity_timeout}).

start_link(Mod, Index) ->
    start_link(Mod, Index, 0).

start_link(Mod, Index, InitialInactivityTimeout) ->
    gen_fsm:start_link(?MODULE, [Mod, Index, InitialInactivityTimeout], []).

%% Send a command message for the vnode module by Pid - 
%% typically to do some deferred processing after returning yourself
send_command(Pid, Request) ->
    gen_fsm:send_event(Pid, ?VNODE_REQ{request=Request}).


%% Sends a command to the FSM that called it after Time 
%% has passed.
-spec send_command_after(integer(), term()) -> reference().
send_command_after(Time, Request) ->
    gen_fsm:send_event_after(Time, ?VNODE_REQ{request=Request}).
    
%% @private
init([Mod, Index, InitialInactivityTimeout]) ->
    %%TODO: Should init args really be an array if it just gets Init?
    process_flag(trap_exit, true),
    {ok, ModState} = Mod:init([Index]),
    riak_core_handoff_manager:remove_exclusion(Mod, Index),
    Timeout = app_helper:get_env(riak_core, vnode_inactivity_timeout, ?DEFAULT_TIMEOUT),
    {ok, active, #state{index=Index, mod=Mod, modstate=ModState,
                        inactivity_timeout=Timeout}, InitialInactivityTimeout}.

get_mod_index(VNode) ->
    gen_fsm:sync_send_all_state_event(VNode, get_mod_index).

continue(State) ->
    {next_state, active, State, State#state.inactivity_timeout}.

continue(State, NewModState) ->
    continue(State#state{modstate=NewModState}).
    

vnode_command(Sender, Request, State=#state{mod=Mod, modstate=ModState}) ->
    case Mod:handle_command(Request, Sender, ModState) of
        {reply, Reply, NewModState} ->
            reply(Sender, Reply),
            continue(State, NewModState);
        {noreply, NewModState} ->
            continue(State, NewModState);
        {stop, Reason, NewModState} ->
            {stop, Reason, State#state{modstate=NewModState}}
    end.

vnode_handoff_command(Sender, Request, State=#state{index=Index,
                                                    mod=Mod, 
                                                    modstate=ModState, 
                                                    handoff_node=HN}) ->
    case Mod:handle_handoff_command(Request, Sender, ModState) of
        {reply, Reply, NewModState} ->
            reply(Sender, Reply),
            continue(State, NewModState);
        {noreply, NewModState} ->
            continue(State, NewModState);
        {forward, NewModState} ->
            riak_core_vnode_master:command({Index, HN}, Request, Sender, 
                                           riak_core_vnode_master:reg_name(Mod)),
            continue(State, NewModState);
        {drop, NewModState} ->
            continue(State, NewModState);
        {stop, Reason, NewModState} ->
            {stop, Reason, State#state{modstate=NewModState}}
    end.

%% @private
active(timeout, State=#state{mod=Mod, modstate=ModState}) ->
    case should_handoff(State) of
        {true, TargetNode} ->
            case Mod:handoff_starting(TargetNode, ModState) of
                {true, NewModState} ->
                    start_handoff(State#state{modstate=NewModState}, TargetNode);
                {false, NewModState} ->
                    continue(State, NewModState)
            end;
        false ->
            continue(State)
    end;
active(?VNODE_REQ{sender=Sender, request=Request},
       State=#state{handoff_node=HN}) when HN =:= none ->
    vnode_command(Sender, Request, State);
active(?VNODE_REQ{sender=Sender, request=Request},State) ->
    vnode_handoff_command(Sender, Request, State);
active(handoff_complete, State=#state{mod=Mod, 
                                      modstate=ModState,
                                      index=Idx, 
                                      handoff_node=HN,
                                      handoff_token=HT}) ->
    riak_core_handoff_manager:release_handoff_lock({Mod, Idx}, HT),
    Mod:handoff_finished(HN, ModState),
    {ok, NewModState} = Mod:delete(ModState),
    riak_core_handoff_manager:add_exclusion(Mod, Idx),
    {stop, normal, State#state{modstate=NewModState, handoff_node=none}}.

%% @private
active(_Event, _From, State) ->
    Reply = ok,
    {reply, Reply, active, State, State#state.inactivity_timeout}.

%% @private
handle_event(R=?VNODE_REQ{}, _StateName, State) ->
    active(R, State).

%% @private
handle_sync_event(get_mod_index, _From, StateName,
                  State=#state{index=Idx,mod=Mod}) ->
    {reply, {Mod, Idx}, StateName, State, State#state.inactivity_timeout};
handle_sync_event({handoff_data,BinObj}, _From, StateName, 
                  State=#state{mod=Mod, modstate=ModState}) ->
    case Mod:handle_handoff_data(BinObj, ModState) of
        {reply, ok, NewModState} ->
            {reply, ok, StateName, State#state{modstate=NewModState},
             State#state.inactivity_timeout};
        {reply, {error, Err}, NewModState} ->
            error_logger:error_msg("Error storing handoff obj: ~p~n", [Err]),            
            {reply, {error, Err}, StateName, State#state{modstate=NewModState}, 
             State#state.inactivity_timeout}
    end.

%% @private
handle_info({'EXIT', Pid, Reason}, StateName, State=#state{mod=Mod}) ->
    %% A linked processes has died so use the
    %% handle_exit callback to allow the vnode 
    %% process to take appropriate action.
    %% If the function is not implemented default
    %% to crashing the process.
    try
        Mod:handle_exit(Pid, Reason, StateName, State)
    catch
        _ErrorType:undef ->
            {stop, linked_process_crash, State}
    end;
handle_info(_Info, StateName, State) ->
    {next_state, StateName, State, State#state.inactivity_timeout}.

%% @private
terminate(Reason, _StateName, #state{mod=Mod, modstate=ModState}) ->
    Mod:terminate(Reason, ModState),
    ok.

%% @private
code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

should_handoff(#state{index=Idx, mod=Mod}) ->
    {ok, Ring} = riak_core_ring_manager:get_my_ring(),
    Me = node(),
    case riak_core_ring:index_owner(Ring, Idx) of
        Me ->
            false;
        TargetNode ->
            ["riak", A, "vnode"] = string:tokens(atom_to_list(Mod), "_"),
            App = list_to_atom("riak_" ++ A),
            case lists:member(TargetNode, riak_core_node_watcher:nodes(App)) of
                false  -> false;
                true -> {true, TargetNode}
            end
    end.

start_handoff(State=#state{index=Idx, mod=Mod, modstate=ModState}, TargetNode) ->
    case Mod:is_empty(ModState) of
        {true, NewModState} ->
            {ok, NewModState1} = Mod:delete(NewModState),
            riak_core_handoff_manager:add_exclusion(Mod, Idx),
            {stop, normal, State#state{modstate=NewModState1}};
        {false, NewModState} ->  
            case riak_core_handoff_manager:get_handoff_lock({Mod, Idx}) of
                {error, max_concurrency} ->
                    {ok, NewModState1} = Mod:handoff_cancelled(NewModState),
                    NewState = State#state{modstate=NewModState1},
                    {next_state, active, NewState, ?LOCK_RETRY_TIMEOUT};
                {ok, {handoff_token, HandoffToken}} ->
                    NewState = State#state{modstate=NewModState, 
                                           handoff_token=HandoffToken,
                                           handoff_node=TargetNode},
                    riak_core_handoff_sender:start_link(TargetNode, Mod, Idx),
                    continue(NewState)
            end
    end.
            

%% @doc Send a reply to a vnode request.  If 
%%      the Ref is undefined just send the reply
%%      for compatibility with pre-0.12 requestors.
%%      If Ref is defined, send it along with the
%%      reply.
%%      
-spec reply(sender(), term()) -> true.
reply({fsm, undefined, From}, Reply) ->
    gen_fsm:send_event(From, Reply);
reply({fsm, Ref, From}, Reply) ->
    gen_fsm:send_event(From, {Ref, Reply});
reply({server, undefined, From}, Reply) ->
    gen_server:reply(From, Reply);
reply({server, Ref, From}, Reply) ->
    gen_server:reply(From, {Ref, Reply});
reply({raw, Ref, From}, Reply) ->
    From ! {Ref, Reply};
reply(ignore, _Reply) ->
    ok.
                   
