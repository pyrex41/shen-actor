\\ Reading actor-language source (ADR 0002).
\\
\\ read-file macroexpands what it reads: unknown heads become curried
\\ applications of fn, so (protocol p ...) arrives as [[fn protocol] p ...].
\\ Protocol, actor and checked forms are read unprocessed instead and handed
\\ to the elaborator as plain s-expressions.  [...] still reads as cons
\\ forms and {...} as the symbols { and }.

(define actor.read-file
  File -> (read-from-string-unprocessed (read-file-as-string File)))
