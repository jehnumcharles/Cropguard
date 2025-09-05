# Policy Bundling System

## Pull Request Title
**Enable bulk crop insurance purchase with progressive discounts**

## Description

This PR introduces a **Policy Bundling** feature to Cropguard, allowing farmers to purchase multiple crop insurance policies simultaneously with tiered bulk discounts. This enhancement improves user experience while encouraging crop diversification through financial incentives.

### Key Features

- **Bulk Policy Creation**: Purchase 2-5 policies in a single transaction with automatic discounts
- **Progressive Discounts**: 5% (2 policies), 10% (3 policies), 15% (4 policies), 20% (5 policies)
- **Crop Diversification**: Prevents duplicate crop types to encourage farming diversity
- **Flexible Execution**: Create bundles upfront, execute individual policies over time
- **Extension Options**: Extend bundle validity periods for additional fees

### Technical Implementation

#### New Storage Maps
- `policy-bundles`: Core bundle metadata including discounts and status
- `bundle-details`: Individual policy specifications within each bundle
- `bundle-policies`: List of executed policy IDs for each bundle
- `farmer-bundles`: Per-farmer bundle tracking for easy lookup

#### Discount Structure
- **2 policies**: 5% discount (`BUNDLE_DISCOUNT_2_POLICIES`)
- **3 policies**: 10% discount (`BUNDLE_DISCOUNT_3_POLICIES`)  
- **4 policies**: 15% discount (`BUNDLE_DISCOUNT_4_POLICIES`)
- **5 policies**: 20% discount (`BUNDLE_DISCOUNT_5_POLICIES`)

#### Public Functions
- `create-policy-bundle(crop-types, premiums, coverages, locations, durations)`: Create discounted bundle
- `purchase-bundled-policy(bundle-id, policy-index)`: Execute individual policy from bundle
- `activate-bundle(bundle-id)`: Reactivate expired bundle
- `extend-bundle-validity(bundle-id, additional-blocks)`: Extend bundle lifetime

#### Read-Only Functions
- `get-policy-bundle(bundle-id)`: Retrieve bundle information
- `get-bundle-savings(bundle-id)`: Calculate total savings achieved
- `calculate-bundle-cost(premiums)`: Preview costs and discounts before purchase
- `is-bundle-active(bundle-id)`: Check bundle status and expiration

### Usage Examples

```clarity
;; Create bundle for corn, wheat, soy with 10% discount (3 policies)
(contract-call? .policy-bundling create-policy-bundle
  (list "corn" "wheat" "soy")
  (list u1000000 u800000 u1200000)
  (list u10000000 u8000000 u12000000)
  (list "Iowa, USA" "Nebraska, USA" "Illinois, USA")
  (list u8640 u8640 u8640))

;; Execute first policy from bundle
(contract-call? .policy-bundling purchase-bundled-policy u1 u0)

;; Check bundle savings
(contract-call? .policy-bundling get-bundle-savings u1)

;; Preview costs before creating bundle
(contract-call? .policy-bundling calculate-bundle-cost 
  (list u1000000 u1200000 u900000))
```

### Benefits

1. **Cost Savings**: Progressive discounts reward farmers for comprehensive coverage
2. **Simplified UX**: Single transaction replaces multiple policy purchases
3. **Risk Diversification**: Crop type validation encourages portfolio diversity
4. **Flexible Timing**: Purchase bundles during planning season, execute when needed
5. **Transparent Pricing**: Clear cost breakdown with savings calculations

### Economic Impact

**Example Scenario**: Farmer purchasing 4 policies
- Individual total: 4,000,000 STX
- Bundle discount: 15% (600,000 STX savings)
- Final cost: 3,400,000 STX
- **Savings: 600,000 STX**

### Validation & Security

- **Crop Uniqueness**: Prevents duplicate crop types within bundles
- **Size Limits**: 2-5 policies per bundle (prevents abuse)
- **Financial Verification**: Balance checks before bundle creation
- **Expiration Handling**: 60-day validity with extension options
- **Authorization**: Only bundle owner can execute policies

### Testing & Deployment

- ✅ Contract compiles successfully with `clarinet check`
- ✅ Complex list processing functions validated
- ✅ Integration with main Cropguard contract confirmed
- ✅ Progressive discount calculations verified
- ✅ Edge case handling implemented

### Contract Size
- **195 lines** - Efficiently under 200 line limit
- Integrates seamlessly with existing Cropguard infrastructure
- Optimized gas usage through batch operations

### Future Enhancements

This foundation enables future features like:
- Seasonal bundle promotions
- Group purchasing for farming cooperatives  
- Dynamic pricing based on market conditions
- Cross-farmer bundle sharing mechanisms

---

**Git Commit Message**: `feat: implement bulk policy bundling with tiered discounts`

This feature transforms how farmers approach crop insurance, making comprehensive coverage more accessible and economically attractive while promoting agricultural diversification.
