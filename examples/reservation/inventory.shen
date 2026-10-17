\\ The inventory actor (ADR 0002).  Data until M2 interprets it.

(actor inventory
  (implements inventory-admission inventory)
  (implements reservation inventory)

  (state
    (stock (map-of (symbol-of widget gadget) (nat-range 0 1000)))
    (available (map-of (symbol-of widget gadget) (nat-range 0 1000)))
    (committed (map-of (symbol-of widget gadget) (nat-range 0 1000))))

  \\ Per-session data lives in the session ledger beside the generation.
  (session-state reservation item-request)

  (init
    (accept [stock [[widget 10] [gadget 5]]
             available [[widget 10] [gadget 5]]
             committed [[widget 0] [gadget 0]]]
            []))

  (handle inventory-admission ready reserve (Request State)
    (let Item (field Request item)
         Qty (field Request quantity)
      (if (>= (lookup Item (field State available)) Qty)
          (accept (update State available Item (- (lookup Item (field State available)) Qty))
                  [(open-session reservation Request)
                   (start-timer lease 30000)
                   (reply reserved)])
          (accept State [(reply insufficient-stock)]))))

  (handle reservation open commit (Held State)
    (let Item (field Held item)
         Qty (field Held quantity)
      (accept (update State committed Item (+ (lookup Item (field State committed)) Qty))
              [(cancel-timer lease) (reply committed)])))

  (handle reservation open cancel (Held State)
    (let Item (field Held item)
         Qty (field Held quantity)
      (accept (update State available Item (+ (lookup Item (field State available)) Qty))
              [(cancel-timer lease) (reply cancelled)])))

  (handle reservation open status (Held State)
    (accept State [(reply open)]))

  \\ Timer events are generation-checked like messages, so a cancelled
  \\ lease that fires late is rejected before reaching this handler.
  (on-timeout reservation open lease (Held State)
    (let Item (field Held item)
         Qty (field Held quantity)
      (accept (update State available Item (+ (lookup Item (field State available)) Qty))
              [])))

  (handle reservation committed status (Held State) (accept State [(reply committed)]))
  (handle reservation cancelled status (Held State) (accept State [(reply cancelled)]))
  (handle reservation expired status (Held State) (accept State [(reply expired)]))

  (invariant stock-conserved
    (forall Item (symbol-of widget gadget)
      (= (lookup Item (field State stock))
         (+ (lookup Item (field State available))
            (+ (held Item)
               (lookup Item (field State committed))))))))
