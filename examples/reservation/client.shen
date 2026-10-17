\\ Checked clients (ADR 0002).  Data until M3 checks them.

(checked reservation-client
  (uses inventory-admission client)
  (uses reservation client)

  \\ Reserve, then commit.  Each send consumes the endpoint it is given;
  \\ await yields one of the four outcomes of PRD section 10.
  (define buy
    {(service inventory-admission) --> operation-id --> operation-id --> symbol}
    Inventory ReserveOp CommitOp ->
      (let Pending (send Inventory reserve ReserveOp [item-request [item widget] [quantity 2]])
        (await Pending
          (succeeded reserved Session (commit-or-report Session CommitOp))
          (succeeded insufficient-stock _ none-available)
          (rejected Reason _ Reason)
          (unavailable no-attempt)
          (outcome-unknown ReserveOp (reconcile-reserve Inventory ReserveOp)))))

  (define commit-or-report
    {(session reservation client open) --> operation-id --> symbol}
    Session Op ->
      (await (send Session commit Op [])
        (succeeded committed _ committed)
        (succeeded expired _ expired)
        (rejected Reason _ Reason)
        (unavailable no-attempt)
        (outcome-unknown Op unknown)))

  \\ Recovery reuses the same operation identifier.
  (define reconcile-reserve
    {(service inventory-admission) --> operation-id --> symbol}
    Inventory Op -> (reconcile Inventory Op)))
