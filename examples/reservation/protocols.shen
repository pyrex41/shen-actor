\\ Reservation service protocols (ADR 0002).  Data until M2 interprets them.

\\ Payload records.  Fields are typed with the transferable types of
\\ PRD section 12; session endpoints never appear in payloads.
(record item-request
  (item (symbol-of widget gadget))
  (quantity (nat-range 1 100)))

\\ Service admission: shareable entry point.  reserve either rejects or
\\ opens a reservation session in which the caller plays client.
(protocol inventory-admission
  (version 1)
  (roles client inventory)
  (initial ready)
  (phase ready
    (message reserve (from client) (to inventory)
      (payload item-request)
      (outcome reserved (opens reservation client) (then ready))
      (outcome insufficient-stock (then ready))))
  (repeatable ready))

\\ One reservation: a ledger entry, not necessarily a process.
(protocol reservation
  (version 1)
  (roles client inventory)
  (initial open)
  (phase open
    (message commit (from client) (to inventory)
      (outcome committed (then committed))
      (outcome expired (then expired)))
    (message cancel (from client) (to inventory)
      (outcome cancelled (then cancelled))
      (outcome expired (then expired)))
    (message status (from client) (to inventory)
      (outcome open (then open)))
    (timeout lease (owner inventory) (then expired)))
  (phase committed
    (message status (from client) (to inventory)
      (outcome committed (then committed))))
  (phase cancelled
    (message status (from client) (to inventory)
      (outcome cancelled (then cancelled))))
  (phase expired
    (message status (from client) (to inventory)
      (outcome expired (then expired))))
  (terminal committed cancelled expired))
