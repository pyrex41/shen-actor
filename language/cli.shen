\\ The actor command line (PRD section 20), run by bin/shen-actor through
\\ shen-erl's launcher: *argv* is [Script | Args].  Every subcommand is a
\\ stub until its milestone; each exits non-zero.

(define actor.commands
  -> ["check" "simulate" "replay" "explain" "build" "run"])

(define actor.usage
  -> "usage: shen-actor check|simulate|replay|explain|build|run ARGS")

(define actor.main
  [_] -> (error (actor.usage))
  [_ Command | _] -> (error "shen-actor ~A: not implemented" Command)
                       where (element? Command (actor.commands))
  [_ Command | _] -> (error "shen-actor: unknown command ~A~%~A" Command (actor.usage)))

(actor.main (value *argv*))
