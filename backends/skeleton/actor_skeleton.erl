%%%-------------------------------------------------------------------
%%% Protocol actor skeleton (plan M1 step 4).
%%%
%%% A hand-written IR for a one-item reservation service, lowered through a
%%% backend candidate to a running gen_server.  Handler bodies are KLambda
%%% defuns compiled by the candidate (Backend:compile/3, the contract
%%% shen_erl_kl_codegen and shen_kl_lfe share); the gen_server shell, session
%%% ledger and validation are the OTP adapter and are the same for both, so
%%% any difference in observable behaviour is the backend's.
%%%
%%% Handlers take (SessionStateOrPayload, DomainState) and return the KL list
%%% [accept NewState Outcome] or [reject Reason].  Domain state is the KL list
%%% [Available Committed].  This is a spike, not the M2 ledger: one item, no
%%% operation ids, no timers.
%%%-------------------------------------------------------------------
-module(actor_skeleton).
-behaviour(gen_server).

-export([ir/0,
         lower/2,
         start/2,
         reserve/2,
         send/3,
         stop/1]).

-export([init/1, handle_call/3, handle_cast/2]).

%%%===================================================================
%%% IR
%%%===================================================================

ir() ->
  #{protocol => reservation,
    initial_state => [5, 0],
    %% Phase -> [{Tag, Handler, Outcome -> NextPhase}]
    phases => #{open => [{commit, 'h-commit', #{committed => committed}},
                         {cancel, 'h-cancel', #{cancelled => cancelled}}],
                committed => [],
                cancelled => []},
    admission => {'h-reserve', #{reserved => open}},
    handlers =>
      [[defun, 'h-reserve', ['Qty', 'State'],
        ['if', ['>=', [hd, 'State'], 'Qty'],
         accept3(state(['-', [hd, 'State'], 'Qty'], [hd, [tl, 'State']]), reserved),
         accept3('State', 'insufficient-stock')]],
       [defun, 'h-commit', ['Held', 'State'],
        accept3(state([hd, 'State'], ['+', [hd, [tl, 'State']], 'Held']), committed)],
       [defun, 'h-cancel', ['Held', 'State'],
        accept3(state(['+', [hd, 'State'], 'Held'], [hd, [tl, 'State']]), cancelled)]]}.

accept3(State, Outcome) -> kl_list([accept, State, Outcome]).
state(Available, Committed) -> kl_list([Available, Committed]).
kl_list([]) -> [];
kl_list([X | Xs]) -> [cons, X, kl_list(Xs)].

%%%===================================================================
%%% Lowering
%%%===================================================================

%% Compile the IR's handlers into module Mod with Backend.  Needs the
%% shen-erl global stores initialised (primitive calls bind statically).
lower(Backend, Mod) ->
  #{handlers := Defuns} = ir(),
  {ok, Mod, Bin} = Backend:compile(Mod, Defuns, ok),
  {module, Mod} = code:load_binary(Mod, atom_to_list(Mod), Bin),
  {ok, Mod}.

%%%===================================================================
%%% Client API
%%%===================================================================

start(HandlerMod, Incarnation) ->
  gen_server:start(?MODULE, {HandlerMod, Incarnation}, []).

reserve(Pid, Qty) -> gen_server:call(Pid, {reserve, Qty}).

%% Token is {Incarnation, SessionId, Generation}.
send(Pid, Token, Tag) -> gen_server:call(Pid, {send, Token, Tag}).

stop(Pid) -> gen_server:stop(Pid).

%%%===================================================================
%%% gen_server
%%%===================================================================

init({HandlerMod, Incarnation}) ->
  #{initial_state := State} = ir(),
  {ok, #{handlers => HandlerMod, incarnation => Incarnation, domain => State,
         sessions => #{}, next => 1}}.

handle_call({reserve, Qty}, _From, S = #{handlers := H, domain := D, next := Id}) ->
  #{admission := {Handler, Opens}} = ir(),
  case H:Handler(Qty, D) of
    [accept, D2, Outcome] ->
      case maps:find(Outcome, Opens) of
        {ok, Phase} ->
          #{sessions := Sessions, incarnation := Inc} = S,
          Session = #{phase => Phase, generation => 0, held => Qty},
          {reply, {Outcome, {Inc, Id, 0}},
           S#{domain => D2, sessions => Sessions#{Id => Session}, next => Id + 1}};
        error ->
          {reply, {Outcome, none}, S#{domain => D2}}
      end;
    [reject, Reason] ->
      {reply, {rejected, 'PreconditionFailed', Reason}, S}
  end;

%% Validation in ADR 0002 order, restricted to what the skeleton models.
handle_call({send, {Inc, Id, Gen}, Tag}, _From, S = #{incarnation := MyInc}) when Inc =/= MyInc ->
  _ = {Id, Gen, Tag},
  {reply, {rejected, 'StaleIncarnation'}, S};
handle_call({send, {_Inc, Id, Gen}, Tag}, _From, S = #{sessions := Sessions}) ->
  case maps:find(Id, Sessions) of
    error -> {reply, {rejected, 'UnknownSession'}, S};
    {ok, #{generation := G}} when G =/= Gen -> {reply, {rejected, 'StaleGeneration'}, S};
    {ok, Session = #{phase := Phase}} ->
      #{phases := Phases} = ir(),
      case lists:keyfind(Tag, 1, maps:get(Phase, Phases)) of
        false -> {reply, {rejected, 'UnexpectedMessage'}, S};
        {Tag, Handler, Next} -> step(Handler, Next, Id, Session, S)
      end
  end.

step(Handler, Next, Id, Session = #{held := Held, generation := G},
     S = #{handlers := H, domain := D, sessions := Sessions, incarnation := Inc}) ->
  case H:Handler(Held, D) of
    [accept, D2, Outcome] ->
      Session2 = Session#{phase => maps:get(Outcome, Next), generation => G + 1},
      {reply, {Outcome, {Inc, Id, G + 1}},
       S#{domain => D2, sessions => Sessions#{Id => Session2}}};
    [reject, Reason] ->
      {reply, {rejected, 'PreconditionFailed', Reason}, S}
  end.

handle_cast(_Msg, S) -> {noreply, S}.
