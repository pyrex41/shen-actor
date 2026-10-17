%%%-------------------------------------------------------------------
%%% Resource probes (plan M0 step 5).
%%%
%%% Measures what repeated evaluation and allocation leave behind on the
%%% pinned shen-erl: loaded modules, atoms, ETS tables and memory.  This is
%%% a measurement, not a test; it prints one row per probe for
%%% tests/BASELINE.md and feeds upstream items U1 and U4.
%%%
%%%   make resource-probes N=1000
%%%-------------------------------------------------------------------
-module(resource_probes).

-export([main/1]).

main([NArg]) ->
  N = list_to_integer(atom_to_list(NArg)),
  boot(),
  io:format("probe,n,modules,atoms,ets_tables,memory_total_kb,memory_code_kb,us_per_op~n"),
  [report(Name, N, Fun) || {Name, Fun} <- probes()],
  halt(0).

probes() ->
  [{eval_kl_expression, fun(I) -> shen_erl_kl_compiler:eval_kl(['+', I, 1]) end},
   {shen_eval_expression, fun(I) -> shen("(+ " ++ integer_to_list(I) ++ " 1)") end},
   {redefine_same_function, fun(I) ->
      shen("(define probe-redef X -> (+ X " ++ integer_to_list(I) ++ "))") end},
   {define_distinct_functions, fun(I) ->
      shen("(define probe-f" ++ integer_to_list(I) ++ " X -> X)") end},
   {absvector, fun(_I) -> shen_erl_kl_primitives:absvector(4) end},
   {shen_dict, fun(_I) -> shen("(shen.dict 8)") end}].

report(Name, N, Fun) ->
  erlang:garbage_collect(),
  Before = sample(),
  T0 = erlang:monotonic_time(microsecond),
  run(Fun, 1, N),
  T1 = erlang:monotonic_time(microsecond),
  erlang:garbage_collect(),
  After = sample(),
  [M, A, E, Mt, Mc] = [Y - X || {X, Y} <- lists:zip(Before, After)],
  io:format("~s,~b,~b,~b,~b,~b,~b,~.1f~n",
            [Name, N, M, A, E, Mt div 1024, Mc div 1024, (T1 - T0) / N]).

run(_Fun, I, N) when I > N -> ok;
run(Fun, I, N) -> Fun(I), run(Fun, I + 1, N).

sample() ->
  [length(code:all_loaded()),
   erlang:system_info(atom_count),
   length(ets:all()),
   erlang:memory(total),
   erlang:memory(code)].

boot() ->
  shen_erl_global_stores:init(),
  shen_erl_kl_primitives:set('*stoutput*', standard_io),
  shen_erl_kl_primitives:set('*stinput*', standard_io),
  shen_erl_kl_compiler:boot().

shen(Source) ->
  shen_erl_kl_compiler:eval(Source).
