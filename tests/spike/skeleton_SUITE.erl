%%%-------------------------------------------------------------------
%%% M1 step 4: the reservation skeleton lowered through each backend
%%% candidate runs as a gen_server, and both give the same trace.
%%% Run by `make spike` (needs LFE on the code path).
%%%-------------------------------------------------------------------
-module(skeleton_SUITE).

-export([suite/0, all/0, init_per_testcase/2, end_per_testcase/2,
         t_erlang_forms/1, t_lfe/1, t_same_trace/1]).

-include_lib("common_test/include/ct.hrl").

suite() -> [{timetrap, {minutes, 2}}].

all() -> [t_erlang_forms, t_lfe, t_same_trace].

%% Handlers bind primitives statically, so the stores must exist; the
%% kernel itself is not booted.
%% shen_kl_erlforms is shen-erl's own shen_erl_kl_codegen compiled under
%% another name (see `make spike`), since the candidate tree's copy of that
%% module is the LFE shim.
init_per_testcase(_Case, Config) ->
  shen_erl_global_stores:init(),
  Config.

end_per_testcase(_Case, _Config) -> ok.

t_erlang_forms(_Config) ->
  Expected = expected(),
  Expected = scenario(shen_kl_erlforms, skeleton_handlers_erl).

t_lfe(_Config) ->
  Expected = expected(),
  Expected = scenario(shen_kl_lfe, skeleton_handlers_lfe).

t_same_trace(_Config) ->
  Trace = scenario(shen_kl_erlforms, skeleton_handlers_erl2),
  Trace = scenario(shen_kl_lfe, skeleton_handlers_lfe2).

%% Stock 5.  Reserve 2, commit; the copied token is then stale.  Reserve 2,
%% cancel.  Reserve 10 is refused.  A token from another incarnation and an
%% unknown session are rejected before any handler runs.
scenario(Backend, Mod) ->
  {ok, Mod} = actor_skeleton:lower(Backend, Mod),
  {ok, P} = actor_skeleton:start(Mod, 1),
  {reserved, T1} = R1 = actor_skeleton:reserve(P, 2),
  C1 = actor_skeleton:send(P, T1, commit),
  C2 = actor_skeleton:send(P, T1, cancel),
  {reserved, T2} = R2 = actor_skeleton:reserve(P, 2),
  X1 = actor_skeleton:send(P, T2, cancel),
  R3 = actor_skeleton:reserve(P, 10),
  {_, Id, Gen} = T2,
  S1 = actor_skeleton:send(P, {0, Id, Gen}, cancel),
  S2 = actor_skeleton:send(P, {1, 99, 0}, commit),
  {_, Id2, _} = element(2, X1),
  S3 = actor_skeleton:send(P, {1, Id2, 1}, commit),
  State = sys:get_state(P),
  actor_skeleton:stop(P),
  [R1, C1, C2, R2, X1, R3, S1, S2, S3, maps:get(domain, State)].

expected() ->
  [{reserved, {1, 1, 0}},
   {committed, {1, 1, 1}},
   {rejected, 'StaleGeneration'},
   {reserved, {1, 2, 0}},
   {cancelled, {1, 2, 1}},
   {'insufficient-stock', none},
   {rejected, 'StaleIncarnation'},
   {rejected, 'UnknownSession'},
   {rejected, 'UnexpectedMessage'},
   [3, 2]].
