\\ Acceptance matrix row 4: a copied endpoint used after commit.
\\ M3's checker must reject this module, naming both sites.
(checked reuse-after-commit
  (uses reservation client)

  (define commit-then-cancel
    {(session reservation client open) --> operation-id --> operation-id --> symbol}
    Session Op1 Op2 ->
      (let Copy Session
           A (send Session commit Op1 [])
           B (send Copy cancel Op2 [])
        both-sent)))
