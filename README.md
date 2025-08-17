# 🌾 Cropguard - Decentralized Crop Insurance DAO

A blockchain-based crop insurance platform that enables farmers to purchase insurance policies and receive automated payouts for verified crop failures through community governance.

## 🚀 Features

- **🛡️ Crop Insurance Policies**: Farmers can purchase customizable insurance policies for their crops
- **🗳️ DAO Governance**: Community members vote on claim approvals through a decentralized voting system
- **💰 Automated Payouts**: Approved claims are automatically processed and paid out
- **📊 Transparent Treasury**: All funds are managed transparently on-chain
- **🔍 Evidence-Based Claims**: Claims require evidence hash for verification

## 📋 Contract Functions

### For Farmers

#### Purchase Insurance Policy
```clarity
(contract-call? .Cropguard purchase-policy premium coverage crop-type location duration-blocks)
```
- `premium`: Amount to pay for insurance (minimum 1 STX)
- `coverage`: Maximum payout amount
- `crop-type`: Type of crop being insured
- `location`: Farm location
- `duration-blocks`: Policy duration in blocks

#### Submit Insurance Claim
```clarity
(contract-call? .Cropguard submit-claim policy-id damage-percentage evidence-hash)
```
- `policy-id`: ID of the insurance policy
- `damage-percentage`: Percentage of crop damage (0-100)
- `evidence-hash`: Hash of evidence supporting the claim

### For DAO Members

#### Join the DAO
```clarity
(contract-call? .Cropguard join-dao stake-amount)
```
- `stake-amount`: STX amount to stake (determines voting power)

#### Vote on Claims
```clarity
(contract-call? .Cropguard vote-on-claim claim-id support)
```
- `claim-id`: ID of the claim to vote on
- `support`: true to approve, false to reject

#### Process Claims
```clarity
(contract-call? .Cropguard process-claim claim-id)
```
- Executes after voting period ends
- Automatically pays out if approved

### Read-Only Functions

#### Get Policy Information
```clarity
(contract-call? .Cropguard get-policy policy-id)
```

#### Get Claim Details
```clarity
(contract-call? .Cropguard get-claim claim-id)
```

#### Check Treasury Balance
```clarity
(contract-call? .Cropguard get-treasury-balance)
```

#### Get Contract Statistics
```clarity
(contract-call? .Cropguard get-contract-stats)
```

## 🔧 Usage Example

### 1. Join the DAO
```bash
clarinet console
```
```clarity
(contract-call? .Cropguard join-dao u5000000)
```

### 2. Purchase Insurance Policy
```clarity
(contract-call? .Cropguard purchase-policy u1000000 u10000000 "corn" "Iowa, USA" u8640)
```

### 3. Submit a Claim
```clarity
(contract-call? .Cropguard submit-claim u1 u75 "abc123def456...")
```


