(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_VOTING_CLOSED (err u104))
(define-constant ERR_INSUFFICIENT_BALANCE (err u105))
(define-constant ERR_REPORT_ALREADY_EXISTS (err u106))
(define-constant ERR_INVALID_STATUS (err u107))

(define-constant VOTING_PERIOD u144)
(define-constant MIN_STAKE_AMOUNT u1000000)
(define-constant REWARD_PERCENTAGE u70)

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
        (company-data (unwrap! (map-get? companies { company-id: company-id }) ERR_NOT_FOUND)))
    (asserts! (get active company-data) ERR_INVALID_STATUS)
    (asserts! (> reward-amount u0) ERR_INVALID_AMOUNT)
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
              (unwrap! (distribute-voter-rewards report-id votes-for total-votes dao-share) ERR_INVALID_AMOUNT)
              (ok true)))
          (begin
            (map-set defect-reports 
              { report-id: report-id }
              (merge report { status: "rejected" }))
            (try! (as-contract (stx-transfer? reward-amount tx-sender (get reporter report))))
            (var-set dao-treasury (- (var-get dao-treasury) reward-amount))
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
