;; Policy Bundling Contract
;; Allows farmers to purchase multiple crop insurance policies at once with bulk discounts

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_INVALID_BUNDLE_SIZE (err u301))
(define-constant ERR_INSUFFICIENT_FUNDS (err u302))
(define-constant ERR_BUNDLE_NOT_FOUND (err u303))
(define-constant ERR_INVALID_AMOUNT (err u304))
(define-constant ERR_DUPLICATE_CROP_TYPE (err u305))
(define-constant ERR_BUNDLE_EXPIRED (err u306))

;; Bundle configuration
(define-constant MIN_BUNDLE_SIZE u2)
(define-constant MAX_BUNDLE_SIZE u5)
(define-constant BUNDLE_DISCOUNT_2_POLICIES u5)   ;; 5% discount for 2 policies
(define-constant BUNDLE_DISCOUNT_3_POLICIES u10)  ;; 10% discount for 3 policies
(define-constant BUNDLE_DISCOUNT_4_POLICIES u15)  ;; 15% discount for 4 policies
(define-constant BUNDLE_DISCOUNT_5_POLICIES u20)  ;; 20% discount for 5 policies
(define-constant BUNDLE_VALIDITY_PERIOD u8640)    ;; ~60 days

;; Data variables
(define-data-var next-bundle-id uint u1)
(define-data-var total-bundles-created uint u0)
(define-data-var total-bundle-premiums uint u0)

;; Bundle policy structure
(define-map policy-bundles uint
    {
        farmer: principal,
        policy-count: uint,
        total-premium: uint,
        discounted-premium: uint,
        discount-percentage: uint,
        bundle-created: uint,
        bundle-expires: uint,
        is-active: bool,
        policies-purchased: uint
    }
)

(define-map bundle-policies uint (list 5 uint))

(define-map bundle-details uint
    {
        crop-types: (list 5 (string-ascii 50)),
        coverages: (list 5 uint),
        locations: (list 5 (string-ascii 100)),
        durations: (list 5 uint),
        individual-premiums: (list 5 uint)
    }
)

(define-map farmer-bundles principal (list 10 uint))

;; Public functions
(define-public (create-policy-bundle 
    (crop-types (list 5 (string-ascii 50)))
    (premiums (list 5 uint))
    (coverages (list 5 uint))
    (locations (list 5 (string-ascii 100)))
    (durations (list 5 uint))
    )
    (let (
        (bundle-id (var-get next-bundle-id))
        (farmer tx-sender)
        (policy-count (len crop-types))
        (total-premium (fold + premiums u0))
        (discount-percent (calculate-bundle-discount policy-count))
        (discount-amount (/ (* total-premium discount-percent) u100))
        (discounted-premium (- total-premium discount-amount))
        (current-balance (stx-get-balance farmer))
    )
        ;; Validation
        (asserts! (and (>= policy-count MIN_BUNDLE_SIZE) (<= policy-count MAX_BUNDLE_SIZE)) ERR_INVALID_BUNDLE_SIZE)
        (asserts! (>= current-balance discounted-premium) ERR_INSUFFICIENT_FUNDS)
        (asserts! (is-eq policy-count (len premiums)) ERR_INVALID_BUNDLE_SIZE)
        (asserts! (is-eq policy-count (len coverages)) ERR_INVALID_BUNDLE_SIZE)
        (asserts! (is-eq policy-count (len locations)) ERR_INVALID_BUNDLE_SIZE)
        (asserts! (is-eq policy-count (len durations)) ERR_INVALID_BUNDLE_SIZE)
        (asserts! (validate-unique-crop-types crop-types) ERR_DUPLICATE_CROP_TYPE)
        
        ;; Payment
        (try! (stx-transfer? discounted-premium farmer (as-contract tx-sender)))
        
        ;; Create bundle
        (map-set policy-bundles bundle-id
            {
                farmer: farmer,
                policy-count: policy-count,
                total-premium: total-premium,
                discounted-premium: discounted-premium,
                discount-percentage: discount-percent,
                bundle-created: stacks-block-height,
                bundle-expires: (+ stacks-block-height BUNDLE_VALIDITY_PERIOD),
                is-active: true,
                policies-purchased: u0
            }
        )
        
        (map-set bundle-details bundle-id
            {
                crop-types: crop-types,
                coverages: coverages,
                locations: locations,
                durations: durations,
                individual-premiums: premiums
            }
        )
        
        ;; Update farmer's bundle list
        (let (
            (farmer-bundle-list (default-to (list) (map-get? farmer-bundles farmer)))
        )
            (map-set farmer-bundles farmer
                (unwrap! (as-max-len? (append farmer-bundle-list bundle-id) u10) ERR_INVALID_AMOUNT)
            )
        )
        
        ;; Update counters
        (var-set next-bundle-id (+ bundle-id u1))
        (var-set total-bundles-created (+ (var-get total-bundles-created) u1))
        (var-set total-bundle-premiums (+ (var-get total-bundle-premiums) discounted-premium))
        
        (ok bundle-id)
    )
)

(define-public (purchase-bundled-policy (bundle-id uint) (policy-index uint))
    (let (
        (bundle (unwrap! (map-get? policy-bundles bundle-id) ERR_BUNDLE_NOT_FOUND))
        (bundle-detail (unwrap! (map-get? bundle-details bundle-id) ERR_BUNDLE_NOT_FOUND))
        (farmer (get farmer bundle))
    )
        (asserts! (is-eq tx-sender farmer) ERR_UNAUTHORIZED)
        (asserts! (get is-active bundle) ERR_BUNDLE_EXPIRED)
        (asserts! (>= (get bundle-expires bundle) stacks-block-height) ERR_BUNDLE_EXPIRED)
        (asserts! (< policy-index (get policy-count bundle)) ERR_INVALID_AMOUNT)
        (asserts! (< (get policies-purchased bundle) (get policy-count bundle)) ERR_INVALID_AMOUNT)
        
        ;; Get policy details
        (let (
            (crop-type (unwrap! (element-at (get crop-types bundle-detail) policy-index) ERR_INVALID_AMOUNT))
            (coverage (unwrap! (element-at (get coverages bundle-detail) policy-index) ERR_INVALID_AMOUNT))
            (location (unwrap! (element-at (get locations bundle-detail) policy-index) ERR_INVALID_AMOUNT))
            (duration (unwrap! (element-at (get durations bundle-detail) policy-index) ERR_INVALID_AMOUNT))
            (premium u0) ;; Already paid in bundle
        )
            ;; Purchase policy through main contract
            (let (
                (policy-id (try! (contract-call? .Cropguard purchase-policy premium coverage crop-type location duration)))
                (existing-policies (default-to (list) (map-get? bundle-policies bundle-id)))
            )
                ;; Update bundle policies
                (map-set bundle-policies bundle-id
                    (unwrap! (as-max-len? (append existing-policies policy-id) u5) ERR_INVALID_AMOUNT)
                )
                
                ;; Update bundle
                (map-set policy-bundles bundle-id
                    (merge bundle { policies-purchased: (+ (get policies-purchased bundle) u1) })
                )
                
                (ok policy-id)
            )
        )
    )
)

(define-public (activate-bundle (bundle-id uint))
    (let (
        (bundle (unwrap! (map-get? policy-bundles bundle-id) ERR_BUNDLE_NOT_FOUND))
        (farmer (get farmer bundle))
    )
        (asserts! (is-eq tx-sender farmer) ERR_UNAUTHORIZED)
        (asserts! (not (get is-active bundle)) ERR_INVALID_AMOUNT)
        (asserts! (>= (get bundle-expires bundle) stacks-block-height) ERR_BUNDLE_EXPIRED)
        
        (map-set policy-bundles bundle-id
            (merge bundle { is-active: true })
        )
        
        (ok true)
    )
)

(define-public (extend-bundle-validity (bundle-id uint) (additional-blocks uint))
    (let (
        (bundle (unwrap! (map-get? policy-bundles bundle-id) ERR_BUNDLE_NOT_FOUND))
        (farmer (get farmer bundle))
        (extension-fee (/ (* (get discounted-premium bundle) u2) u100)) ;; 2% of premium
    )
        (asserts! (is-eq tx-sender farmer) ERR_UNAUTHORIZED)
        (asserts! (get is-active bundle) ERR_BUNDLE_EXPIRED)
        (asserts! (>= (stx-get-balance farmer) extension-fee) ERR_INSUFFICIENT_FUNDS)
        
        (try! (stx-transfer? extension-fee farmer (as-contract tx-sender)))
        
        (map-set policy-bundles bundle-id
            (merge bundle { 
                bundle-expires: (+ (get bundle-expires bundle) additional-blocks)
            })
        )
        
        (ok (+ (get bundle-expires bundle) additional-blocks))
    )
)

;; Read-only functions
(define-read-only (get-policy-bundle (bundle-id uint))
    (map-get? policy-bundles bundle-id)
)

(define-read-only (get-bundle-details (bundle-id uint))
    (map-get? bundle-details bundle-id)
)

(define-read-only (get-bundle-policies (bundle-id uint))
    (default-to (list) (map-get? bundle-policies bundle-id))
)

(define-read-only (get-farmer-bundles (farmer principal))
    (default-to (list) (map-get? farmer-bundles farmer))
)

(define-read-only (calculate-bundle-discount (policy-count uint))
    (if (is-eq policy-count u2) BUNDLE_DISCOUNT_2_POLICIES
        (if (is-eq policy-count u3) BUNDLE_DISCOUNT_3_POLICIES
            (if (is-eq policy-count u4) BUNDLE_DISCOUNT_4_POLICIES
                (if (is-eq policy-count u5) BUNDLE_DISCOUNT_5_POLICIES
                    u0
                )
            )
        )
    )
)

(define-read-only (get-bundle-savings (bundle-id uint))
    (match (map-get? policy-bundles bundle-id)
        bundle (some {
            total-premium: (get total-premium bundle),
            discounted-premium: (get discounted-premium bundle),
            savings: (- (get total-premium bundle) (get discounted-premium bundle)),
            discount-percentage: (get discount-percentage bundle)
        })
        none
    )
)

(define-read-only (is-bundle-active (bundle-id uint))
    (match (map-get? policy-bundles bundle-id)
        bundle (and 
            (get is-active bundle)
            (>= (get bundle-expires bundle) stacks-block-height)
        )
        false
    )
)

(define-read-only (get-bundling-stats)
    {
        next-bundle-id: (var-get next-bundle-id),
        total-bundles-created: (var-get total-bundles-created),
        total-bundle-premiums: (var-get total-bundle-premiums),
        bundle-discounts: {
            two-policies: BUNDLE_DISCOUNT_2_POLICIES,
            three-policies: BUNDLE_DISCOUNT_3_POLICIES,
            four-policies: BUNDLE_DISCOUNT_4_POLICIES,
            five-policies: BUNDLE_DISCOUNT_5_POLICIES
        }
    }
)

(define-read-only (calculate-bundle-cost 
    (premiums (list 5 uint))
    )
    (let (
        (policy-count (len premiums))
        (total-premium (fold + premiums u0))
        (discount-percent (calculate-bundle-discount policy-count))
        (discount-amount (/ (* total-premium discount-percent) u100))
        (discounted-premium (- total-premium discount-amount))
    )
        {
            policy-count: policy-count,
            total-premium: total-premium,
            discount-percentage: discount-percent,
            discount-amount: discount-amount,
            final-cost: discounted-premium
        }
    )
)

;; Private functions
(define-private (validate-unique-crop-types (crop-types (list 5 (string-ascii 50))))
    (let (
        (unique-crops (fold check-crop-uniqueness crop-types (list)))
    )
        (is-eq (len crop-types) (len unique-crops))
    )
)

(define-private (check-crop-uniqueness (crop (string-ascii 50)) (unique-list (list 5 (string-ascii 50))))
    (if (is-none (index-of unique-list crop))
        (unwrap! (as-max-len? (append unique-list crop) u5) unique-list)
        unique-list
    )
)
