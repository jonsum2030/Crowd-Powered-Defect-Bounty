(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_VOTING_CLOSED (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_REPORT_ALREADY_EXISTS (err u106))
(define-constant ERR_INVALID_STATUS (err u107))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u108))

(define-constant VOTING_PERIOD u144)
(define-constant MIN_STAKE_AMOUNT u1000000)
(define-constant REWARD_PERCENTAGE u70)
(define-constant REPUTATION_THRESHOLD u50)
(define-constant MAX_REPUTATION_SCORE u100)
(define-constant ESCALATION_FEE_PERCENTAGE u50)
(define-constant MAX_ESCALATIONS u2)

(define-data-var next-report-id uint u1)
(define-data-var total-staked uint u0)
(define-data-var dao-treasury uint u0)

(define-map companies 
  { company-id: uint } 
  { 
    name: (string-ascii 64),
    owner: principal,
    stake-amount: uint,
    active: bool
  })

(define-map defect-reports 
  { report-id: uint }
  {
    reporter: principal,
    company-id: uint,
    product-name: (string-ascii 64),
    defect-description: (string-ascii 256),
    evidence-hash: (string-ascii 64),
    reward-amount: uint,
    status: (string-ascii 16),
    votes-for: uint,
    votes-against: uint,
    voting-ends: uint,
    created-at: uint
  })

(define-map company-counter 
  { dummy: bool } 
  { count: uint })

(define-map voter-records
  { report-id: uint, voter: principal }
  { vote: bool, stake: uint })

(define-map user-balances
  { user: principal }
  { balance: uint })

(define-map dao-members
  { member: principal }
  { stake: uint, joined-at: uint })

(define-map reporter-reputation
  { reporter: principal }
  {
    total-reports: uint,
    approved-reports: uint,
    rejected-reports: uint,
    reputation-score: uint,
    total-rewards: uint,
    last-updated: uint
  }
)

(define-map report-escalations
  { report-id: uint }
  {
    escalation-count: uint,
    current-escalation: uint,
    last-escalated-at: uint,
    escalation-fee-paid: uint
  }
)

(define-map escalation-details
  { report-id: uint, escalation-number: uint }
  {
    new-evidence-hash: (string-ascii 64),
    additional-description: (string-ascii 256),
    votes-for: uint,
    votes-against: uint,
    voting-ends: uint,
    status: (string-ascii 16),
    escalated-by: principal,
    created-at: uint
  }
)

(define-map escalation-voter-records
  { report-id: uint, escalation-number: uint, voter: principal }
  { vote: bool, stake: uint })

(define-public (register-company (name (string-ascii 64)) (stake-amount uint))
  (let ((company-id (default-to u0 (get count (map-get? company-counter { dummy: true })))))
    (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set companies 
      { company-id: (+ company-id u1) }
      {
        name: name,
        owner: tx-sender,
        stake-amount: stake-amount,
        active: true
      })
    (map-set company-counter { dummy: true } { count: (+ company-id u1) })
    (var-set total-staked (+ (var-get total-staked) stake-amount))
    (ok (+ company-id u1))))

(define-public (join-dao (stake-amount uint))
  (begin
    (asserts! (>= stake-amount MIN_STAKE_AMOUNT) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (map-set dao-members 
      { member: tx-sender }
      { 
        stake: (+ stake-amount (default-to u0 (get stake (map-get? dao-members { member: tx-sender })))),
        joined-at: stacks-block-height
      })
    (var-set total-staked (+ (var-get total-staked) stake-amount))
    (ok true)))

(define-public (submit-defect-report 
  (company-id uint)
  (product-name (string-ascii 64))
  (defect-description (string-ascii 256))
  (evidence-hash (string-ascii 64))
  (reward-amount uint))
  (let ((report-id (var-get next-report-id))
        (company-data (unwrap! (map-get? companies { company-id: company-id }) ERR_NOT_FOUND))
        (reporter-rep (get-reporter-reputation tx-sender)))
    (asserts! (get active company-data) ERR_INVALID_STATUS)
    (asserts! (> reward-amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get reputation-score reporter-rep) REPUTATION_THRESHOLD) ERR_INSUFFICIENT_REPUTATION)
    (try! (stx-transfer? reward-amount tx-sender (as-contract tx-sender)))
    (map-set defect-reports 
      { report-id: report-id }
      {
        reporter: tx-sender,
        company-id: company-id,
        product-name: product-name,
        defect-description: defect-description,
        evidence-hash: evidence-hash,
        reward-amount: reward-amount,
        status: "pending",
        votes-for: u0,
        votes-against: u0,
        voting-ends: (+ stacks-block-height VOTING_PERIOD),
        created-at: stacks-block-height
      })
    (unwrap-panic (update-reporter-stats tx-sender u1 u0 u0))
    (var-set next-report-id (+ report-id u1))
    (var-set dao-treasury (+ (var-get dao-treasury) reward-amount))
    (ok report-id)))

(define-public (vote-on-report (report-id uint) (vote-for bool))
  (let ((report (unwrap! (map-get? defect-reports { report-id: report-id }) ERR_NOT_FOUND))
        (voter-stake (default-to u0 (get stake (map-get? dao-members { member: tx-sender }))))
        (existing-vote (map-get? voter-records { report-id: report-id, voter: tx-sender })))
    (asserts! (> voter-stake u0) ERR_UNAUTHORIZED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (<= stacks-block-height (get voting-ends report)) ERR_VOTING_CLOSED)
    (asserts! (is-eq (get status report) "pending") ERR_INVALID_STATUS)
    
    (map-set voter-records 
      { report-id: report-id, voter: tx-sender }
      { vote: vote-for, stake: voter-stake })
    
    (if vote-for
      (map-set defect-reports 
        { report-id: report-id }
        (merge report { votes-for: (+ (get votes-for report) voter-stake) }))
      (map-set defect-reports 
        { report-id: report-id }
        (merge report { votes-against: (+ (get votes-against report) voter-stake) })))
    (ok true)))

(define-public (finalize-report (report-id uint))
  (let ((report (unwrap! (map-get? defect-reports { report-id: report-id }) ERR_NOT_FOUND)))
    (asserts! (> stacks-block-height (get voting-ends report)) ERR_VOTING_CLOSED)
    (asserts! (is-eq (get status report) "pending") ERR_INVALID_STATUS)
    
    (let ((votes-for (get votes-for report))
          (votes-against (get votes-against report))
          (total-votes (+ votes-for votes-against))
          (approved (and (> total-votes u0) (> votes-for votes-against)))
          (reward-amount (get reward-amount report)))
      
      (begin
        (if approved
          (begin
            (map-set defect-reports 
              { report-id: report-id }
              (merge report { status: "approved" }))
            (let ((reporter-reward (/ (* reward-amount REWARD_PERCENTAGE) u100))
                  (dao-share (- reward-amount reporter-reward)))
              (try! (as-contract (stx-transfer? reporter-reward tx-sender (get reporter report))))
              (var-set dao-treasury (- (var-get dao-treasury) reporter-reward))
              (unwrap-panic (update-reporter-stats (get reporter report) u0 u1 reporter-reward))
              (unwrap! (distribute-voter-rewards report-id votes-for total-votes dao-share) ERR_INVALID_AMOUNT)
              (ok true)))
          (begin
            (map-set defect-reports 
              { report-id: report-id }
              (merge report { status: "rejected" }))
            (try! (as-contract (stx-transfer? reward-amount tx-sender (get reporter report))))
            (var-set dao-treasury (- (var-get dao-treasury) reward-amount))
            (unwrap-panic (update-reporter-stats (get reporter report) u0 u0 u1))
            (ok false)))))))

(define-private (distribute-voter-rewards (report-id uint) (winning-votes uint) (total-votes uint) (reward-pool uint))
  (ok true))

(define-public (withdraw-stake)
  (let ((member-data (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_FOUND))
        (stake-amount (get stake member-data)))
    (asserts! (> stake-amount u0) ERR_INVALID_AMOUNT)
    (map-delete dao-members { member: tx-sender })
    (var-set total-staked (- (var-get total-staked) stake-amount))
    (as-contract (stx-transfer? stake-amount tx-sender tx-sender))))

(define-public (deactivate-company (company-id uint))
  (let ((company (unwrap! (map-get? companies { company-id: company-id }) ERR_NOT_FOUND)))
    (asserts! (is-eq tx-sender (get owner company)) ERR_UNAUTHORIZED)
    (map-set companies 
      { company-id: company-id }
      (merge company { active: false }))
    (as-contract (stx-transfer? (get stake-amount company) tx-sender (get owner company)))))

(define-read-only (get-report (report-id uint))
  (map-get? defect-reports { report-id: report-id }))

(define-read-only (get-company (company-id uint))
  (map-get? companies { company-id: company-id }))

(define-read-only (get-dao-member (member principal))
  (map-get? dao-members { member: member }))

(define-read-only (get-voter-record (report-id uint) (voter principal))
  (map-get? voter-records { report-id: report-id, voter: voter }))

(define-read-only (get-next-report-id)
  (var-get next-report-id))

(define-read-only (get-total-staked)
  (var-get total-staked))

(define-read-only (get-dao-treasury)
  (var-get dao-treasury))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))

(define-read-only (is-voting-active (report-id uint))
  (match (map-get? defect-reports { report-id: report-id })
    report (and 
            (is-eq (get status report) "pending")
            (<= stacks-block-height (get voting-ends report)))
    false))

(define-read-only (get-company-count)
  (default-to u0 (get count (map-get? company-counter { dummy: true }))))

(define-private (update-reporter-stats (reporter principal) (new-reports uint) (approved uint) (rejected uint))
  (let ((current-rep (get-reporter-reputation reporter)))
    (let ((new-total (+ (get total-reports current-rep) new-reports))
          (new-approved (+ (get approved-reports current-rep) approved))
          (new-rejected (+ (get rejected-reports current-rep) rejected))
          (new-score (if (> new-total u0)
                        (/ (* new-approved u100) new-total)
                        u100)))
      (map-set reporter-reputation 
        { reporter: reporter }
        {
          total-reports: new-total,
          approved-reports: new-approved,
          rejected-reports: new-rejected,
          reputation-score: (if (> new-score MAX_REPUTATION_SCORE) MAX_REPUTATION_SCORE new-score),
          total-rewards: (+ (get total-rewards current-rep) (if (> approved u0) u1 u0)),
          last-updated: stacks-block-height
        })
      (ok true)
    )
  )
)

(define-private (get-reporter-reputation (reporter principal))
  (default-to 
    {
      total-reports: u0,
      approved-reports: u0,
      rejected-reports: u0,
      reputation-score: u100,
      total-rewards: u0,
      last-updated: u0
    }
    (map-get? reporter-reputation { reporter: reporter })
  )
)

(define-read-only (get-reputation (reporter principal))
  (map-get? reporter-reputation { reporter: reporter })
)

(define-read-only (get-reputation-score (reporter principal))
  (get reputation-score (get-reporter-reputation reporter))
)

(define-read-only (is-eligible-reporter (reporter principal))
  (>= (get-reputation-score reporter) REPUTATION_THRESHOLD)
)

(define-public (escalate-report
  (report-id uint)
  (new-evidence-hash (string-ascii 64))
  (additional-description (string-ascii 256)))
  (let ((report (unwrap! (map-get? defect-reports { report-id: report-id }) ERR_NOT_FOUND))
        (escalation-data (default-to 
          { escalation-count: u0, current-escalation: u0, last-escalated-at: u0, escalation-fee-paid: u0 }
          (map-get? report-escalations { report-id: report-id })))
        (escalation-fee (/ (* (get reward-amount report) ESCALATION_FEE_PERCENTAGE) u100)))
    (begin
      (asserts! (is-eq (get reporter report) tx-sender) ERR_UNAUTHORIZED)
      (asserts! (is-eq (get status report) "rejected") ERR_INVALID_STATUS)
      (asserts! (< (get escalation-count escalation-data) MAX_ESCALATIONS) ERR_INVALID_STATUS)
      (asserts! (> escalation-fee u0) ERR_INVALID_AMOUNT)
      (try! (stx-transfer? escalation-fee tx-sender (as-contract tx-sender)))
      (let ((new-escalation-number (+ (get escalation-count escalation-data) u1)))
        (map-set report-escalations
          { report-id: report-id }
          {
            escalation-count: new-escalation-number,
            current-escalation: new-escalation-number,
            last-escalated-at: stacks-block-height,
            escalation-fee-paid: (+ (get escalation-fee-paid escalation-data) escalation-fee)
          })
        (map-set escalation-details
          { report-id: report-id, escalation-number: new-escalation-number }
          {
            new-evidence-hash: new-evidence-hash,
            additional-description: additional-description,
            votes-for: u0,
            votes-against: u0,
            voting-ends: (+ stacks-block-height VOTING_PERIOD),
            status: "pending",
            escalated-by: tx-sender,
            created-at: stacks-block-height
          })
        (var-set dao-treasury (+ (var-get dao-treasury) escalation-fee))
        (ok new-escalation-number)))))

(define-public (vote-on-escalation (report-id uint) (escalation-number uint) (vote-for bool))
  (let ((escalation (unwrap! (map-get? escalation-details 
                               { report-id: report-id, escalation-number: escalation-number }) ERR_NOT_FOUND))
        (voter-stake (default-to u0 (get stake (map-get? dao-members { member: tx-sender }))))
        (existing-vote (map-get? escalation-voter-records 
                        { report-id: report-id, escalation-number: escalation-number, voter: tx-sender })))
    (begin
      (asserts! (> voter-stake u0) ERR_UNAUTHORIZED)
      (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
      (asserts! (<= stacks-block-height (get voting-ends escalation)) ERR_VOTING_CLOSED)
      (asserts! (is-eq (get status escalation) "pending") ERR_INVALID_STATUS)
      (map-set escalation-voter-records
        { report-id: report-id, escalation-number: escalation-number, voter: tx-sender }
        { vote: vote-for, stake: voter-stake })
      (if vote-for
        (map-set escalation-details
          { report-id: report-id, escalation-number: escalation-number }
          (merge escalation { votes-for: (+ (get votes-for escalation) voter-stake) }))
        (map-set escalation-details
          { report-id: report-id, escalation-number: escalation-number }
          (merge escalation { votes-against: (+ (get votes-against escalation) voter-stake) })))
      (ok true))))

(define-public (finalize-escalation (report-id uint) (escalation-number uint))
  (let ((escalation (unwrap! (map-get? escalation-details 
                               { report-id: report-id, escalation-number: escalation-number }) ERR_NOT_FOUND))
        (report (unwrap! (map-get? defect-reports { report-id: report-id }) ERR_NOT_FOUND)))
    (begin
      (asserts! (> stacks-block-height (get voting-ends escalation)) ERR_VOTING_CLOSED)
      (asserts! (is-eq (get status escalation) "pending") ERR_INVALID_STATUS)
      (let ((votes-for (get votes-for escalation))
            (votes-against (get votes-against escalation))
            (total-votes (+ votes-for votes-against))
            (approved (and (> total-votes u0) (> votes-for votes-against)))
            (reward-amount (get reward-amount report)))
        (if approved
          (begin
            (map-set escalation-details
              { report-id: report-id, escalation-number: escalation-number }
              (merge escalation { status: "approved" }))
            (map-set defect-reports
              { report-id: report-id }
              (merge report { status: "approved" }))
            (let ((reporter-reward (/ (* reward-amount REWARD_PERCENTAGE) u100))
                  (dao-share (- reward-amount reporter-reward)))
              (try! (as-contract (stx-transfer? reporter-reward tx-sender (get reporter report))))
              (var-set dao-treasury (- (var-get dao-treasury) reporter-reward))
              (unwrap-panic (update-reporter-stats (get reporter report) u0 u1 u0))
              (ok true)))
          (begin
            (map-set escalation-details
              { report-id: report-id, escalation-number: escalation-number }
              (merge escalation { status: "rejected" }))
            (ok false)))))))

(define-read-only (get-escalation-status (report-id uint))
  (map-get? report-escalations { report-id: report-id }))

(define-read-only (get-escalation-details (report-id uint) (escalation-number uint))
  (map-get? escalation-details { report-id: report-id, escalation-number: escalation-number }))

(define-read-only (get-escalation-voter-record (report-id uint) (escalation-number uint) (voter principal))
  (map-get? escalation-voter-records { report-id: report-id, escalation-number: escalation-number, voter: voter }))

(define-read-only (is-escalation-voting-active (report-id uint) (escalation-number uint))
  (match (map-get? escalation-details { report-id: report-id, escalation-number: escalation-number })
    escalation (and 
                (is-eq (get status escalation) "pending")
                (<= stacks-block-height (get voting-ends escalation)))
    false))

(define-read-only (calculate-escalation-fee (report-id uint))
  (match (map-get? defect-reports { report-id: report-id })
    report (ok (/ (* (get reward-amount report) ESCALATION_FEE_PERCENTAGE) u100))
    ERR_NOT_FOUND))

(define-read-only (can-escalate-report (report-id uint) (reporter principal))
  (match (map-get? defect-reports { report-id: report-id })
    report
    (let ((escalation-data (default-to 
            { escalation-count: u0, current-escalation: u0, last-escalated-at: u0, escalation-fee-paid: u0 }
            (map-get? report-escalations { report-id: report-id }))))
      (and
        (is-eq (get reporter report) reporter)
        (is-eq (get status report) "rejected")
        (< (get escalation-count escalation-data) MAX_ESCALATIONS)))
    false))
