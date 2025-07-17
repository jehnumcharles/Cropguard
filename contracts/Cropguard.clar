;; title: Cropguard
;; version: 1.0.0
;; summary: Decentralized crop insurance DAO for farmers
;; description: A DAO-based crop insurance platform where farmers can purchase policies and receive automated payouts for verified crop failures

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_POLICY_NOT_FOUND (err u101))
(define-constant ERR_INSUFFICIENT_FUNDS (err u102))
(define-constant ERR_POLICY_EXPIRED (err u103))
(define-constant ERR_POLICY_ALREADY_EXISTS (err u104))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u105))
(define-constant ERR_INVALID_AMOUNT (err u106))
(define-constant ERR_VOTING_PERIOD_ENDED (err u107))
(define-constant ERR_ALREADY_VOTED (err u108))
(define-constant ERR_CLAIM_NOT_FOUND (err u109))
(define-constant ERR_INSUFFICIENT_VOTES (err u110))
(define-constant ERR_ORACLE_NOT_AUTHORIZED (err u111))
(define-constant ERR_WEATHER_DATA_NOT_FOUND (err u112))
(define-constant ERR_INVALID_WEATHER_DATA (err u113))
(define-constant ERR_ORACLE_ALREADY_EXISTS (err u114))
(define-constant ERR_WEATHER_TRIGGER_NOT_MET (err u115))

(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var treasury-balance uint u0)
(define-data-var min-premium uint u1000000)
(define-data-var max-coverage uint u100000000)
(define-data-var voting-period uint u144)
(define-data-var next-weather-report-id uint u1)
(define-data-var oracle-registration-fee uint u5000000)
(define-data-var weather-data-validity-period uint u144)

(define-map policies
  { policy-id: uint }
  {
    farmer: principal,
    premium: uint,
    coverage: uint,
    crop-type: (string-ascii 50),
    location: (string-ascii 100),
    start-block: uint,
    end-block: uint,
    active: bool
  }
)

(define-map claims
  {
    claim-id: uint
  }
  {
    policy-id: uint,
    farmer: principal,
    damage-percentage: uint,
    evidence-hash: (string-ascii 64),
    claim-amount: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    voting-end-block: uint,
    processed: bool
  }
)

(define-map farmer-policies
  { farmer: principal }
  { policy-ids: (list 50 uint) }
)

(define-map claim-votes
  { claim-id: uint, voter: principal }
  { vote: bool, voted: bool }
)

(define-map dao-members
  { member: principal }
  { stake: uint, voting-power: uint, joined-block: uint }
)

(define-map weather-oracles
  { oracle-id: principal }
  {
    name: (string-ascii 50),
    registration-block: uint,
    stake: uint,
    reputation-score: uint,
    total-reports: uint,
    active: bool
  }
)

(define-map weather-reports
  { report-id: uint }
  {
    oracle-id: principal,
    location: (string-ascii 100),
    temperature: int,
    humidity: uint,
    precipitation: uint,
    wind-speed: uint,
    weather-condition: (string-ascii 30),
    timestamp: uint,
    block-height: uint,
    verified: bool
  }
)

(define-map policy-weather-triggers
  { policy-id: uint }
  {
    min-temperature: int,
    max-temperature: int,
    max-wind-speed: uint,
    max-precipitation: uint,
    trigger-conditions: (list 10 (string-ascii 30)),
    monitoring-active: bool,
    last-checked-block: uint
  }
)

(define-map weather-claims
  { claim-id: uint }
  {
    policy-id: uint,
    weather-report-id: uint,
    trigger-type: (string-ascii 30),
    auto-triggered: bool,
    trigger-block: uint
  }
)

(define-public (join-dao (stake-amount uint))
  (let
    (
      (current-balance (stx-get-balance tx-sender))
    )
    (asserts! (>= current-balance stake-amount) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> stake-amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) stake-amount))
    (map-set dao-members
      { member: tx-sender }
      {
        stake: stake-amount,
        voting-power: (/ stake-amount u1000000),
        joined-block: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (purchase-policy (premium uint) (coverage uint) (crop-type (string-ascii 50)) (location (string-ascii 100)) (duration-blocks uint))
  (let
    (
      (policy-id (var-get next-policy-id))
      (current-balance (stx-get-balance tx-sender))
      (existing-policies (default-to { policy-ids: (list) } (map-get? farmer-policies { farmer: tx-sender })))
    )
    (asserts! (>= premium (var-get min-premium)) ERR_INVALID_AMOUNT)
    (asserts! (<= coverage (var-get max-coverage)) ERR_INVALID_AMOUNT)
    (asserts! (>= current-balance premium) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> duration-blocks u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) premium))
    
    (map-set policies
      { policy-id: policy-id }
      {
        farmer: tx-sender,
        premium: premium,
        coverage: coverage,
        crop-type: crop-type,
        location: location,
        start-block: stacks-block-height,
        end-block: (+ stacks-block-height duration-blocks),
        active: true
      }
    )
    
    (map-set farmer-policies
      { farmer: tx-sender }
      { policy-ids: (unwrap! (as-max-len? (append (get policy-ids existing-policies) policy-id) u50) ERR_INVALID_AMOUNT) }
    )
    
    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

(define-public (submit-claim (policy-id uint) (damage-percentage uint) (evidence-hash (string-ascii 64)))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
      (claim-id (var-get next-claim-id))
      (claim-amount (/ (* (get coverage policy) damage-percentage) u100))
    )
    (asserts! (is-eq (get farmer policy) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get active policy) ERR_POLICY_EXPIRED)
    (asserts! (<= stacks-block-height (get end-block policy)) ERR_POLICY_EXPIRED)
    (asserts! (<= damage-percentage u100) ERR_INVALID_AMOUNT)
    
    (map-set claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        farmer: tx-sender,
        damage-percentage: damage-percentage,
        evidence-hash: evidence-hash,
        claim-amount: claim-amount,
        status: "pending",
        votes-for: u0,
        votes-against: u0,
        voting-end-block: (+ stacks-block-height (var-get voting-period)),
        processed: false
      }
    )
    
    (var-set next-claim-id (+ claim-id u1))
    (ok claim-id)
  )
)

(define-public (vote-on-claim (claim-id uint) (support bool))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR_CLAIM_NOT_FOUND))
      (voter-info (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_AUTHORIZED))
      (existing-vote (map-get? claim-votes { claim-id: claim-id, voter: tx-sender }))
      (voting-power (get voting-power voter-info))
    )
    (asserts! (< stacks-block-height (get voting-end-block claim)) ERR_VOTING_PERIOD_ENDED)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (not (get processed claim)) ERR_CLAIM_ALREADY_PROCESSED)
    
    (map-set claim-votes
      { claim-id: claim-id, voter: tx-sender }
      { vote: support, voted: true }
    )
    
    (map-set claims
      { claim-id: claim-id }
      (merge claim
        {
          votes-for: (if support (+ (get votes-for claim) voting-power) (get votes-for claim)),
          votes-against: (if support (get votes-against claim) (+ (get votes-against claim) voting-power))
        }
      )
    )
    (ok true)
  )
)
(define-public (process-claim (claim-id uint))
  (let
    (
      (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR_CLAIM_NOT_FOUND))
      (total-votes (+ (get votes-for claim) (get votes-against claim)))
      (approval-threshold (/ total-votes u2))
    )
    (asserts! (>= stacks-block-height (get voting-end-block claim)) ERR_VOTING_PERIOD_ENDED)
    (asserts! (not (get processed claim)) ERR_CLAIM_ALREADY_PROCESSED)
    (asserts! (>= total-votes u3) ERR_INSUFFICIENT_VOTES)
    
    (if (> (get votes-for claim) approval-threshold)
      (begin
        (asserts! (>= (var-get treasury-balance) (get claim-amount claim)) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? (get claim-amount claim) tx-sender (get farmer claim))))
        (var-set treasury-balance (- (var-get treasury-balance) (get claim-amount claim)))
        (map-set claims
          { claim-id: claim-id }
          (merge claim { status: "approved", processed: true })
        )
        (ok "approved")
      )
      (begin
        (map-set claims
          { claim-id: claim-id }
          (merge claim { status: "rejected", processed: true })
        )
        (ok "rejected")
      )
    )
  )
)

(define-public (update-policy-status (policy-id uint) (active bool))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
    )
    (asserts! (is-eq (get farmer policy) tx-sender) ERR_NOT_AUTHORIZED)
    (map-set policies
      { policy-id: policy-id }
      (merge policy { active: active })
    )
    (ok true)
  )
)

(define-public (withdraw-dao-stake)
  (let
    (
      (member-info (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_AUTHORIZED))
      (stake-amount (get stake member-info))
    )
    (asserts! (>= (var-get treasury-balance) stake-amount) ERR_INSUFFICIENT_FUNDS)
    (try! (as-contract (stx-transfer? stake-amount tx-sender tx-sender)))
    (var-set treasury-balance (- (var-get treasury-balance) stake-amount))
    (map-delete dao-members { member: tx-sender })
    (ok stake-amount)
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

(define-read-only (get-claim (claim-id uint))
  (map-get? claims { claim-id: claim-id })
)

(define-read-only (get-farmer-policies (farmer principal))
  (map-get? farmer-policies { farmer: farmer })
)

(define-read-only (get-dao-member (member principal))
  (map-get? dao-members { member: member })
)

(define-read-only (get-treasury-balance)
  (var-get treasury-balance)
)

(define-read-only (get-contract-stats)
  {
    next-policy-id: (var-get next-policy-id),
    next-claim-id: (var-get next-claim-id),
    treasury-balance: (var-get treasury-balance),
    min-premium: (var-get min-premium),
    max-coverage: (var-get max-coverage),
    voting-period: (var-get voting-period)
  }
)

(define-read-only (get-claim-vote (claim-id uint) (voter principal))
  (map-get? claim-votes { claim-id: claim-id, voter: voter })
)

(define-read-only (is-policy-active (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy (and (get active policy) (<= stacks-block-height (get end-block policy)))
    false
  )
)

(define-public (register-weather-oracle (oracle-name (string-ascii 50)))
  (let
    (
      (registration-fee (var-get oracle-registration-fee))
      (current-balance (stx-get-balance tx-sender))
      (existing-oracle (map-get? weather-oracles { oracle-id: tx-sender }))
    )
    (asserts! (is-none existing-oracle) ERR_ORACLE_ALREADY_EXISTS)
    (asserts! (>= current-balance registration-fee) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> (len oracle-name) u0) ERR_INVALID_AMOUNT)
    
    (try! (stx-transfer? registration-fee tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) registration-fee))
    
    (map-set weather-oracles
      { oracle-id: tx-sender }
      {
        name: oracle-name,
        registration-block: stacks-block-height,
        stake: registration-fee,
        reputation-score: u100,
        total-reports: u0,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (submit-weather-report (location (string-ascii 100)) (temperature int) (humidity uint) (precipitation uint) (wind-speed uint) (weather-condition (string-ascii 30)))
  (let
    (
      (oracle-info (unwrap! (map-get? weather-oracles { oracle-id: tx-sender }) ERR_ORACLE_NOT_AUTHORIZED))
      (report-id (var-get next-weather-report-id))
    )
    (asserts! (get active oracle-info) ERR_ORACLE_NOT_AUTHORIZED)
    (asserts! (> (len location) u0) ERR_INVALID_WEATHER_DATA)
    (asserts! (<= humidity u100) ERR_INVALID_WEATHER_DATA)
    (asserts! (> (len weather-condition) u0) ERR_INVALID_WEATHER_DATA)
    
    (map-set weather-reports
      { report-id: report-id }
      {
        oracle-id: tx-sender,
        location: location,
        temperature: temperature,
        humidity: humidity,
        precipitation: precipitation,
        wind-speed: wind-speed,
        weather-condition: weather-condition,
        timestamp: (unwrap-panic (get-stacks-block-info? time stacks-block-height)),
        block-height: stacks-block-height,
        verified: false
      }
    )
    
    (map-set weather-oracles
      { oracle-id: tx-sender }
      (merge oracle-info { total-reports: (+ (get total-reports oracle-info) u1) })
    )
    
    (var-set next-weather-report-id (+ report-id u1))
    (ok report-id)
  )
)

(define-public (verify-weather-report (report-id uint))
  (let
    (
      (report (unwrap! (map-get? weather-reports { report-id: report-id }) ERR_WEATHER_DATA_NOT_FOUND))
      (oracle-info (unwrap! (map-get? weather-oracles { oracle-id: (get oracle-id report) }) ERR_ORACLE_NOT_AUTHORIZED))
      (voter-info (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_AUTHORIZED))
    )
    (asserts! (not (get verified report)) ERR_CLAIM_ALREADY_PROCESSED)
    (asserts! (>= (get voting-power voter-info) u1) ERR_NOT_AUTHORIZED)
    
    (map-set weather-reports
      { report-id: report-id }
      (merge report { verified: true })
    )
    
    (map-set weather-oracles
      { oracle-id: (get oracle-id report) }
      (merge oracle-info { reputation-score: (+ (get reputation-score oracle-info) u10) })
    )
    
    (ok true)
  )
)

(define-public (set-policy-weather-triggers (policy-id uint) (min-temp int) (max-temp int) (max-wind uint) (max-precip uint) (conditions (list 10 (string-ascii 30))))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
    )
    (asserts! (is-eq (get farmer policy) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get active policy) ERR_POLICY_EXPIRED)
    (asserts! (< min-temp max-temp) ERR_INVALID_WEATHER_DATA)
    
    (map-set policy-weather-triggers
      { policy-id: policy-id }
      {
        min-temperature: min-temp,
        max-temperature: max-temp,
        max-wind-speed: max-wind,
        max-precipitation: max-precip,
        trigger-conditions: conditions,
        monitoring-active: true,
        last-checked-block: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (check-weather-triggers (policy-id uint) (weather-report-id uint))
  (let
    (
      (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR_POLICY_NOT_FOUND))
      (weather-report (unwrap! (map-get? weather-reports { report-id: weather-report-id }) ERR_WEATHER_DATA_NOT_FOUND))
      (weather-triggers (unwrap! (map-get? policy-weather-triggers { policy-id: policy-id }) ERR_WEATHER_DATA_NOT_FOUND))
      (claim-id (var-get next-claim-id))
    )
    (asserts! (get active policy) ERR_POLICY_EXPIRED)
    (asserts! (get verified weather-report) ERR_INVALID_WEATHER_DATA)
    (asserts! (get monitoring-active weather-triggers) ERR_WEATHER_TRIGGER_NOT_MET)
    (asserts! (is-eq (get location policy) (get location weather-report)) ERR_INVALID_WEATHER_DATA)
    
    (let
      (
        (temperature (get temperature weather-report))
        (wind-speed (get wind-speed weather-report))
        (precipitation (get precipitation weather-report))
        (weather-condition (get weather-condition weather-report))
        (trigger-met (or
          (< temperature (get min-temperature weather-triggers))
          (> temperature (get max-temperature weather-triggers))
          (> wind-speed (get max-wind-speed weather-triggers))
          (> precipitation (get max-precipitation weather-triggers))
          (is-some (index-of (get trigger-conditions weather-triggers) weather-condition))
        ))
      )
      (asserts! trigger-met ERR_WEATHER_TRIGGER_NOT_MET)
      
      (map-set claims
        { claim-id: claim-id }
        {
          policy-id: policy-id,
          farmer: (get farmer policy),
          damage-percentage: u80,
          evidence-hash: "weather-auto-trigger",
          claim-amount: (/ (* (get coverage policy) u80) u100),
          status: "weather-triggered",
          votes-for: u0,
          votes-against: u0,
          voting-end-block: (+ stacks-block-height (var-get voting-period)),
          processed: false
        }
      )
      
      (map-set weather-claims
        { claim-id: claim-id }
        {
          policy-id: policy-id,
          weather-report-id: weather-report-id,
          trigger-type: weather-condition,
          auto-triggered: true,
          trigger-block: stacks-block-height
        }
      )
      
      (var-set next-claim-id (+ claim-id u1))
      (ok claim-id)
    )
  )
)

(define-public (deactivate-oracle (oracle-id principal))
  (let
    (
      (oracle-info (unwrap! (map-get? weather-oracles { oracle-id: oracle-id }) ERR_ORACLE_NOT_AUTHORIZED))
      (caller-dao-info (unwrap! (map-get? dao-members { member: tx-sender }) ERR_NOT_AUTHORIZED))
    )
    (asserts! (>= (get voting-power caller-dao-info) u5) ERR_NOT_AUTHORIZED)
    (asserts! (get active oracle-info) ERR_ORACLE_NOT_AUTHORIZED)
    
    (map-set weather-oracles
      { oracle-id: oracle-id }
      (merge oracle-info { active: false })
    )
    (ok true)
  )
)

(define-read-only (get-weather-oracle (oracle-id principal))
  (map-get? weather-oracles { oracle-id: oracle-id })
)

(define-read-only (get-weather-report (report-id uint))
  (map-get? weather-reports { report-id: report-id })
)

(define-read-only (get-policy-weather-triggers (policy-id uint))
  (map-get? policy-weather-triggers { policy-id: policy-id })
)

(define-read-only (get-weather-claim (claim-id uint))
  (map-get? weather-claims { claim-id: claim-id })
)

(define-read-only (get-weather-stats)
  {
    next-weather-report-id: (var-get next-weather-report-id),
    oracle-registration-fee: (var-get oracle-registration-fee),
    weather-data-validity-period: (var-get weather-data-validity-period)
  }
)