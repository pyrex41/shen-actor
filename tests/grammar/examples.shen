\\ The ADR 0002 examples read as the frontend will read them.  Prints each
\\ top-level form's kind and name with its phases and messages, handlers,
\\ or definitions, so a grammar change that moves structure shows up here.
(load "../../language/read.shen")

(define pick
  _ [] -> []
  Tag [[Tag | Item] | Rest] -> [[Tag | Item] | (pick Tag Rest)]
  Tag [_ | Rest] -> (pick Tag Rest))

(define messages
  [] -> []
  [[message Tag | _] | Rest] -> [Tag | (messages Rest)]
  [[timeout Name | _] | Rest] -> [[timeout Name] | (messages Rest)]
  [_ | Rest] -> (messages Rest))

(define event
  [Protocol Phase Event | _] -> [Protocol Phase Event])

(define summary
  [record Name | _] -> [record Name]
  [protocol Name | Body] ->
    [protocol Name (map (/. P [(hd (tl P)) | (messages (tl (tl P)))]) (pick phase Body))]
  [actor Name | Body] ->
    [actor Name
      (map (/. H (hd (tl H))) (pick implements Body))
      (map (/. H (event (tl H))) (append (pick handle Body) (pick on-timeout Body)))
      (map (/. I (hd (tl I))) (pick invariant Body))]
  [checked Name | Body] ->
    [checked Name (map (/. U (tl U)) (pick uses Body)) (map (/. D (hd (tl D))) (pick define Body))]
  Form -> [unrecognised Form])

(define show
  File -> (do (output "~A~%" File)
              (map (/. F (output "  ~S~%" (summary F))) (actor.read-file File))
              done))

(show "../../examples/reservation/protocols.shen")
(show "../../examples/reservation/inventory.shen")
(show "../../examples/reservation/client.shen")
(show "../../examples/reservation/reuse-rejected.shen")
