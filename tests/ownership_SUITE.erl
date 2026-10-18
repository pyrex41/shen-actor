%%%-------------------------------------------------------------------
%%% Ownership probes (plan M0 step 3).
%%%
%%% shen-erl's stores are named, protected ETS tables owned by whichever
%%% process calls shen_erl_global_stores:init/0.  Each case here makes the
%%% test case process the owner, boots the kernel, then performs one
%%% operation from a second process and asserts the outcome observed on the
%%% pinned shen-erl.  These assert today's behaviour, not the desired one:
%%% when upstream items U1 and U2 land and the pin is bumped, the failing
%%% probes flip to success in the same change (plan section 4, M4).
%%%-------------------------------------------------------------------
-module(ownership_SUITE).

-export([suite/0,
         all/0,
         init_per_testcase/2,
         end_per_testcase/2,
         t_read_global/1,
         t_read_global_via_eval/1,
         t_set_global/1,
         t_set_global_via_eval/1,
         t_create_vector/1,
         t_read_owner_vector/1,
         t_write_owner_vector/1,
         t_eval_kl_expression/1,
         t_eval_kl_defun/1,
         t_define_function/1,
         t_call_defined_function/1,
         t_variable_counter/1,
         t_stores_die_with_owner/1]).

-include_lib("common_test/include/ct.hrl").

-define(REMOTE_TIMEOUT, 30000).

%%%===================================================================
%%% Common test
%%%===================================================================

suite() ->
  [{timetrap, {minutes, 2}}].

all() ->
  [t_read_global,
   t_read_global_via_eval,
   t_set_global,
   t_set_global_via_eval,
   t_create_vector,
   t_read_owner_vector,
   t_write_owner_vector,
   t_eval_kl_expression,
   t_eval_kl_defun,
   t_define_function,
   t_call_defined_function,
   t_variable_counter,
   t_stores_die_with_owner].

%% The test case process owns the stores, as the launcher's init process does.
init_per_testcase(t_stores_die_with_owner, Config) ->
  Config;
init_per_testcase(_Case, Config) ->
  shen_erl_global_stores:init(),
  shen_erl_kl_primitives:set('*stoutput*', standard_io),
  shen_erl_kl_primitives:set('*stinput*', standard_io),
  shen_erl_kl_compiler:boot(),
  shen("(set probe-global 1)"),
  shen("(define probe-id X -> X)"),
  [{vector, shen("(@v a b c <>)")} | Config].

end_per_testcase(_Case, _Config) ->
  ok.

%%%===================================================================
%%% Globals
%%%===================================================================

t_read_global(_Config) ->
  {ok, 1} = remote(fun() -> shen_erl_kl_primitives:value('probe-global') end).

t_read_global_via_eval(_Config) ->
  {ok, 1} = remote(fun() -> shen("(value probe-global)") end).

t_set_global(_Config) ->
  {error, badarg} = remote(fun() -> shen_erl_kl_primitives:set('probe-global', 2) end),
  1 = shen("(value probe-global)").

t_set_global_via_eval(_Config) ->
  {error, badarg} = remote(fun() -> shen("(set probe-global 3)") end),
  1 = shen("(value probe-global)").

%%%===================================================================
%%% Vectors
%%%===================================================================

%% absvector/1 calls dict_new/0, which bumps the shared variable counter.
t_create_vector(_Config) ->
  {error, badarg} = remote(fun() -> shen_erl_kl_primitives:absvector(3) end).

t_read_owner_vector(Config) ->
  V = ?config(vector, Config),
  {ok, b} = remote(fun() -> shen_erl_kl_primitives:'<-address'(V, 2) end).

t_write_owner_vector(Config) ->
  V = ?config(vector, Config),
  {error, badarg} = remote(fun() -> shen_erl_kl_primitives:'address->'(V, 2, z) end),
  b = shen_erl_kl_primitives:'<-address'(V, 2).

%%%===================================================================
%%% Evaluation and definitions
%%%===================================================================

%% A non-defun form compiles to a fresh random module and writes no store,
%% so it succeeds from any process.  The plan (section 1) expected every
%% compile to fail; this probe records that it does not.
t_eval_kl_expression(_Config) ->
  {ok, 3} = remote(fun() -> shen_erl_kl_compiler:eval_kl(['+', 1, 2]) end).

%% A defun registers its MFA in the function store before compiling.
t_eval_kl_defun(_Config) ->
  {error, badarg} =
    remote(fun() -> shen_erl_kl_compiler:eval_kl([defun, 'probe-k', ['X'], 'X']) end).

t_define_function(_Config) ->
  {error, badarg} = remote(fun() -> shen("(define probe-g X -> X)") end).

t_call_defined_function(_Config) ->
  {ok, 7} = remote(fun() -> shen_erl_kl_compiler:invoke('probe-id', [7]) end),
  {ok, 7} = remote(fun() -> shen("(probe-id 7)") end).

t_variable_counter(_Config) ->
  {error, badarg} = remote(fun() -> shen_erl_global_stores:get_varname() end).

%%%===================================================================
%%% Lifetime
%%%===================================================================

%% Nothing supervises the stores: when the owner exits they are gone.
t_stores_die_with_owner(_Config) ->
  {Owner, Ref} = spawn_monitor(fun() ->
    shen_erl_global_stores:init(),
    shen_erl_kl_primitives:set('probe-global', 1)
  end),
  receive {'DOWN', Ref, process, Owner, normal} -> ok
  after ?REMOTE_TIMEOUT -> ct:fail(owner_did_not_exit)
  end,
  undefined = ets:info('_kl_values_store'),
  not_found = shen_erl_global_stores:get_val('probe-global').

%%%===================================================================
%%% Helpers
%%%===================================================================

shen(Source) ->
  shen_erl_kl_compiler:eval(Source).

%% Run Fun in a fresh process; report {ok, Value} or {Class, Reason}, with
%% the reason cut to its tag so assertions do not depend on stack details.
remote(Fun) ->
  Self = self(),
  Ref = make_ref(),
  spawn(fun() ->
    Result = try {ok, Fun()} catch Class:Reason -> {Class, tag(Reason)} end,
    Self ! {Ref, Result}
  end),
  receive {Ref, Result} -> Result
  after ?REMOTE_TIMEOUT -> ct:fail(remote_timeout)
  end.

tag(Reason) when is_tuple(Reason), tuple_size(Reason) > 0 -> element(1, Reason);
tag(Reason) -> Reason.
