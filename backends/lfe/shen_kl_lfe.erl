%%%-------------------------------------------------------------------
%%% KLambda to LFE emitter (plan M1, backend spike).
%%%
%%% Takes the KL AST from shen_erl_kl_parse and emits LFE forms, which
%%% lfe_comp compiles to BEAM.  Everything else is the pinned shen-erl
%%% unchanged: primitives, overrides, global stores, the runtime dispatch
%%% shen_erl_kl_compiler:invoke/2.  The rules mirror
%%% shen_erl_kl_codegen clause for clause, so a divergence is the emitter's.
%%%
%%% Two deliberate differences:
%%% - Variable names come from a counter local to each compile, not from the
%%%   shared variable counter in ETS, so compiling writes no store.
%%% - Ten kernel function names are LFE core forms or core functions
%%%   (function, call, receive, when, ==, get, put, length, map, not), which
%%%   LFE refuses to define.  Every defun is emitted under a prefixed name,
%%%   compiled to Core Erlang, renamed back there, and finished with
%%%   compile:forms(from_core).  LFE's own extra exports are dropped so the
%%%   boot's export-based registration sees only Shen functions.
%%%-------------------------------------------------------------------
-module(shen_kl_lfe).

-export([compile/3,
         forms/3]).

-record(env, {vars = #{} :: #{atom() => atom()},
              next :: reference()}).

%%%===================================================================
%%% API
%%%===================================================================

%% Same contract as shen_erl_kl_codegen:compile/3.
-spec compile(module(), list(), atom()) -> {ok, module(), binary()} | {error, term()}.
compile(Mod, ToplevelDefs, DefaultTle) ->
  Forms = forms(Mod, ToplevelDefs, DefaultTle),
  case lfe_comp:forms(Forms, [return, to_core, no_docs]) of
    {ok, [{ok, Mod, Core, _Warnings}], _} ->
      case compile:forms(unprefix(Core), [from_core, binary, return]) of
        {ok, Mod, Bin, _} -> {ok, Mod, Bin};
        {error, Errors, Warnings} -> {error, {Errors, Warnings}}
      end;
    {error, Errors, Warnings} -> {error, {Errors, Warnings}};
    Other -> {error, Other}
  end.

-spec forms(module(), list(), atom()) -> [term()].
forms(Mod, ToplevelDefs, DefaultTle) ->
  Counter = make_ref(),
  put(Counter, 0),
  try
    {Defuns, Tles} = toplevel(last_defuns(ToplevelDefs), Counter, [], []),
    Exports = [[kl_tle, 0] | [[Name, length(Args)] || [defun, Name, Args | _] <- Defuns]],
    %% Defuns and exports carry prefixed names; unprefix/1 restores them.
    [[defmodule, Mod, [export | Exports]],
     [defun, kl_tle, [] | [[quote, DefaultTle] | Tles]]
     | Defuns]
  after
    erase(Counter)
  end.

%%%===================================================================
%%% Toplevel
%%%===================================================================

toplevel([[defun, Name, Args, Body] | Rest], Counter, Defuns, Tles) ->
  {LArgs, Env} = bind_all(Args, new_env(Counter)),
  Defun = [defun, prefixed(Name), LArgs, exp(Body, Env)],
  toplevel(Rest, Counter, [Defun | Defuns], Tles);
toplevel([Exp | Rest], Counter, Defuns, Tles) when is_list(Exp) ->
  toplevel(Rest, Counter, Defuns, [exp(Exp, new_env(Counter)) | Tles]);
toplevel([_Exp | Rest], Counter, Defuns, Tles) ->
  toplevel(Rest, Counter, Defuns, Tles);
toplevel([], _Counter, Defuns, Tles) ->
  {lists:reverse(Defuns), lists:reverse(Tles)}.

%% As shen_erl_kl_codegen: the last definition of a name in a file wins.
last_defuns(ToplevelDefs) ->
  Last = maps:from_list([{Name, Def} || Def = [defun, Name, _Args, _Body] <- ToplevelDefs]),
  {Kept, _Seen} =
    lists:foldr(fun (Def = [defun, Name, _Args, _Body], {Acc, Seen}) ->
                      case {maps:get(Name, Last) =:= Def, maps:is_key(Name, Seen)} of
                        {true, false} -> {[Def | Acc], Seen#{Name => true}};
                        _ -> {Acc, Seen}
                      end;
                    (Exp, {Acc, Seen}) -> {[Exp | Acc], Seen}
                end, {[], #{}}, ToplevelDefs),
  Kept.

-define(PREFIX, "shen-kl:").

prefixed(Name) -> list_to_atom(?PREFIX ++ atom_to_list(Name)).

%% Restore defun names in Core Erlang and keep only kl_tle, module_info and
%% the Shen functions as exports.
unprefix(Core) ->
  Rename = fun (FName) ->
               {Name, Arity} = cerl:var_name(FName),
               case lists:prefix(?PREFIX, atom_to_list(Name)) of
                 true -> {shen, cerl:c_fname(list_to_atom(lists:nthtail(length(?PREFIX), atom_to_list(Name))), Arity)};
                 false -> {other, FName}
               end
           end,
  Exports = [case Rename(E) of
               {shen, E2} -> E2;
               {other, E2} -> E2
             end || E <- cerl:module_exports(Core),
                    begin {N, _} = cerl:var_name(E),
                          lists:prefix(?PREFIX, atom_to_list(N))
                            orelse N =:= kl_tle orelse N =:= module_info
                    end],
  Defs = [{element(2, Rename(F)), D} || {F, D} <- cerl:module_defs(Core)],
  cerl:update_c_module(Core, cerl:module_name(Core), Exports, cerl:module_attrs(Core), Defs).

%%%===================================================================
%%% Expressions
%%%===================================================================

exp([], _Env) ->
  [quote, []];

exp(['and', A, B], Env) ->
  ['andalso', exp(force_boolean(A), Env), exp(force_boolean(B), Env)];
exp(['or', A, B], Env) ->
  ['orelse', exp(force_boolean(A), Env), exp(force_boolean(B), Env)];
exp(['not', A], Env) ->
  ['not', exp(force_boolean(A), Env)];

exp(Sym, Env) when is_atom(Sym) ->
  case fetch(Sym, Env) of
    {ok, Var} -> Var;
    not_found -> [quote, Sym]
  end;

exp(N, _Env) when is_number(N) ->
  N;

exp(Str = {string, _}, _Env) ->
  [quote, Str];

%% See shen_erl_kl_codegen: compiler-generated eta expansions of user
%% functions dispatch at run time so a later redefinition is observed.
exp(Exp = [lambda, Var, Body], Env) when is_atom(Var) ->
  case dynamic_eta_app(Exp) of
    {ok, Op, Args} -> runtime_app(Op, [exp(Arg, Env) || Arg <- Args]);
    no ->
      {LVar, Env2} = bind(Var, Env),
      [lambda, [LVar], exp(Body, Env2)]
  end;

exp(['let', Var, Value, Body], Env) when is_atom(Var) ->
  LValue = exp(Value, Env),
  {LVar, Env2} = bind(Var, Env),
  ['let', [[LVar, LValue]], exp(Body, Env2)];

exp(['type', Exp, _Type], Env) ->
  exp(Exp, Env);

exp(['if', C, T, F], Env) ->
  ['case', exp(force_boolean(C), Env),
   [[quote, true], exp(T, Env)],
   [[quote, false], exp(F, Env)]];

exp(['cond', [C, T]], Env) ->
  ['case', exp(force_boolean(C), Env),
   [[quote, true], exp(T, Env)]];
exp(['cond', [C, T] | Rest], Env) ->
  ['case', exp(force_boolean(C), Env),
   [[quote, true], exp(T, Env)],
   [[quote, false], exp(['cond' | Rest], Env)]];

exp([freeze, Body], Env) ->
  [lambda, [], exp(Body, Env)];

%% The handler receives {Class, Reason}, as in shen_erl_kl_codegen.
exp(['trap-error', Body, Handler], Env) ->
  {Class, Env2} = fresh(Env),
  {Reason, Env3} = fresh(Env2),
  {Stack, _Env4} = fresh(Env3),
  ['try', exp(Body, Env),
   ['catch',
    [[tuple, Class, Reason, Stack],
     [funcall, exp(Handler, Env), [tuple, Class, Reason]]]]];

exp(['%%let-label', [Label | Vars], LabelBody, Body], Env) ->
  {LVars, LabelEnv} = bind_all(Vars, Env),
  {LLabel, Env2} = bind(Label, Env),
  ['let', [[LLabel, [lambda, LVars, exp(LabelBody, LabelEnv)]]], exp(Body, Env2)];
exp(['%%goto-label', Label | Args], Env) ->
  {ok, LLabel} = fetch(Label, Env),
  [funcall, LLabel | [exp(Arg, Env) || Arg <- Args]];
exp(['%%return', Exp], Env) ->
  exp(Exp, Env);

exp(['intern', {string, Name}], _Env) ->
  [quote, list_to_atom(Name)];

exp(['thaw', Exp], Env) ->
  exp([Exp], Env);

exp([Op | Args], Env) when is_atom(Op) ->
  LArgs = [exp(Arg, Env) || Arg <- Args],
  case fetch(Op, Env) of
    {ok, Var} -> dynamic_app(Var, LArgs);
    not_found ->
      case shen_erl_global_stores:get_mfa(Op) of
        {ok, {Mod, Fun, Arity}} ->
          case is_dynamic_function(Op, Mod) of
            true -> runtime_app(Op, LArgs);
            false -> static_app(Mod, Fun, Arity, LArgs, Env)
          end;
        not_found -> runtime_app(Op, LArgs)
      end
  end;

exp([Op | Args], Env) ->
  dynamic_app(exp(Op, Env), [exp(Arg, Env) || Arg <- Args]).

%%%===================================================================
%%% Applications
%%%===================================================================

dynamic_app(F, []) -> [funcall, F];
dynamic_app(F, [A]) -> [funcall, F, A];
dynamic_app(F, [A | Rest]) -> dynamic_app([funcall, F, A], Rest).

static_app(Mod, Fun, Arity, Args, _Env) when Arity =:= length(Args) ->
  [call, [quote, Mod], [quote, Fun] | Args];
static_app(Mod, Fun, Arity, Args, Env) when Arity > length(Args) ->
  {Var, Env2} = fresh(Env),
  [lambda, [Var], static_app(Mod, Fun, Arity, Args ++ [Var], Env2)];
static_app(Mod, Fun, Arity, Args, Env) ->
  {Static, Dynamic} = lists:split(Arity, Args),
  dynamic_app(static_app(Mod, Fun, Arity, Static, Env), Dynamic).

runtime_app(Op, Args) ->
  [call, [quote, shen_erl_kl_compiler], [quote, invoke], [quote, Op], [list | Args]].

dynamic_eta_app(Exp) ->
  dynamic_eta_app(Exp, []).

dynamic_eta_app([lambda, Var, Body], Vars) when is_atom(Var) ->
  dynamic_eta_app(Body, Vars ++ [Var]);
dynamic_eta_app([Op | Args], Vars) when is_atom(Op), Vars =/= [] ->
  PrefixLen = length(Args) - length(Vars),
  case PrefixLen > 0 andalso lists:nthtail(PrefixLen, Args) =:= Vars of
    true ->
      case shen_erl_global_stores:get_mfa(Op) of
        {ok, {Mod, _Fun, _Arity}} ->
          case is_dynamic_function(Op, Mod) of
            true -> {ok, Op, lists:sublist(Args, PrefixLen)};
            false -> no
          end;
        not_found -> no
      end;
    false -> no
  end;
dynamic_eta_app(_Exp, _Vars) ->
  no.

is_dynamic_function('shen.demod', _Mod) -> true;
is_dynamic_function(_Op, Mod) -> lists:prefix("_kl_", atom_to_list(Mod)).

%%%===================================================================
%%% Booleans (as shen_erl_kl_codegen)
%%%===================================================================

yields_boolean(true) -> true;
yields_boolean(false) -> false;                %% as the original, which wraps it
yields_boolean(['let', _Var, _Value, Body]) -> yields_boolean(Body);
yields_boolean(['do', _A, B]) -> yields_boolean(B);
yields_boolean([Op, _A, _B]) when Op =:= 'or'; Op =:= 'and'; Op =:= '<'; Op =:= '>';
                                  Op =:= '>='; Op =:= '<='; Op =:= '=' ->
  true;
yields_boolean([Op, _A]) when Op =:= 'not'; Op =:= 'string?'; Op =:= 'vector?';
                              Op =:= 'number?'; Op =:= 'cons?'; Op =:= 'absvector?';
                              Op =:= 'element?'; Op =:= 'symbol?'; Op =:= 'tuple?';
                              Op =:= 'variable?'; Op =:= 'boolean?'; Op =:= 'empty?';
                              Op =:= 'shen.pvar?' ->
  true;
yields_boolean(_Exp) -> false.

force_boolean(Exp) ->
  case yields_boolean(Exp) of
    true -> Exp;
    false -> ['assert-boolean', Exp]
  end.

%%%===================================================================
%%% Variables
%%%===================================================================

new_env(Counter) -> #env{next = Counter}.

fetch(Sym, #env{vars = Vars}) ->
  case maps:find(Sym, Vars) of
    {ok, Var} -> {ok, Var};
    error -> not_found
  end.

bind(Sym, Env = #env{vars = Vars}) ->
  {Var, Env2} = fresh(Env),
  {Var, Env2#env{vars = Vars#{Sym => Var}}}.

bind_all(Syms, Env) ->
  lists:foldr(fun (Sym, {Acc, E}) -> {Var, E2} = bind(Sym, E), {[Var | Acc], E2} end,
              {[], Env}, Syms).

fresh(Env = #env{next = Counter}) ->
  N = get(Counter) + 1,
  put(Counter, N),
  {list_to_atom("v" ++ integer_to_list(N)), Env}.
