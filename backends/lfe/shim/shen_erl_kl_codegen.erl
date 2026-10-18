%%%-------------------------------------------------------------------
%%% Drop-in replacement for shen-erl's shen_erl_kl_codegen that compiles
%%% through the LFE emitter (plan M1).  Installed only into the spike's copy
%%% of the pinned tree (backends/lfe/build.sh), never into deps/shen-erl.
%%% Same exports and side effects as the original; only compile/3 differs.
%%%-------------------------------------------------------------------
-module(shen_erl_kl_codegen).

-export([load_defuns/2,
         eval/1,
         compile/1,
         compile/3]).

load_defuns(Mod, ToplevelDefs) ->
  [shen_erl_global_stores:set_mfa(Name, {Mod, Name, length(Args)}) ||
    [defun, Name, Args, _Body] <- ToplevelDefs, is_atom(Name), is_list(Args)],
  ok.

eval(ToplevelDef) ->
  {ok, Mod, Bin} = compile(ToplevelDef),
  {module, Mod} = code:load_binary(Mod, [], Bin),
  Mod:kl_tle().

compile(ToplevelDef = [defun, Name, Args, _Body]) ->
  Mod = list_to_atom("_kl_" ++ atom_to_list(Name)),
  shen_erl_global_stores:set_mfa(Name, {Mod, Name, length(Args)}),
  compile(Mod, [ToplevelDef], Name);
compile(ToplevelDef) ->
  compile(rand_modname(32, []), [ToplevelDef], ok).

compile(Mod, ToplevelDefs, DefaultTle) ->
  shen_kl_lfe:compile(Mod, ToplevelDefs, DefaultTle).

rand_modname(0, Acc) ->
  list_to_atom("_kl_" ++ Acc);
rand_modname(N, Acc) ->
  rand_modname(N - 1, [rand:uniform(26) + 96 | Acc]).
