# 🔍 Crowd-Powered Defect Bounty

A decentralized platform for crowdsourced product defect reporting and validation, built on the Stacks blockchain.

## 🎯 Overview

The Crowd-Powered Defect Bounty smart contract enables consumers to report product defects and earn STX rewards when their reports are confirmed by a decentralized autonomous organization (DAO). Companies can register on the platform, and DAO members vote on the validity of defect reports.

## ✨ Key Features

- 🏢 **Company Registration**: Companies can join by staking STX tokens
- 📋 **Defect Reporting**: Consumers submit detailed defect reports with evidence
- 🗳️ **DAO Voting**: Decentralized validation of defect reports
- 💰 **Reward System**: Automatic STX distribution for valid reports
- 🔒 **Stake-Based Governance**: Voting power based on staked amounts

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts
- STX tokens for testing

### Installation

1. Clone the repository:
```bash
git clone https://github.com/jonsum2030/Crowd-Powered-Defect-Bounty.git
cd Crowd-Powered-Defect-Bounty
```

2. Install dependencies:
```bash
npm install
```

3. Run tests:
```bash
clarinet test
```

## 📖 Usage Guide

### 🏢 For Companies

#### Register Your Company
```clarity
(contract-call? .crowd-powered-defect-bounty register-company "My Company" u5000000)
```
- Minimum stake: 1,000,000 microSTX (1 STX)
- Companies must maintain active status to receive reports

#### Deactivate Company
```clarity
(contract-call? .crowd-powered-defect-bounty deactivate-company u1)
```

### 👥 For DAO Members

#### Join the DAO
```clarity
(contract-call? .crowd-powered-defect-bounty join-dao u2000000)
```
- Minimum stake: 1,000,000 microSTX
- Voting power proportional to stake amount

#### Vote on Reports
```clarity
(contract-call? .crowd-powered-defect-bounty vote-on-report u1 true)
```
- `true` = approve defect report
- `false` = reject defect report

#### Withdraw Stake
```clarity
(contract-call? .crowd-powered-defect-bounty withdraw-stake)
```

### 🐛 For Defect Reporters

#### Submit a Defect Report
```clarity
(contract-call? .crowd-powered-defect-bounty submit-defect-report 
  u1 
  "Product Name" 
  "Detailed defect description with steps to reproduce"
  "evidence-hash-ipfs"
  u1000000)
```

#### Finalize Report (after voting period)
```clarity
(contract-call? .crowd-powered-defect-bounty finalize-report u1)
```

## 🔧 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `register-company` | 🏢 Register a new company | `name`, `stake-amount` |
| `join-dao` | 👥 Join the DAO with stake | `stake-amount` |
| `submit-defect-report` | 📋 Submit a defect report | `company-id`, `product-name`, `description`, `evidence-hash`, `reward-amount` |
| `vote-on-report` | 🗳️ Vote on a defect report | `report-id`, `vote-for` |
| `finalize-report` | ✅ Finalize voting results | `report-id` |
| `withdraw-stake` | 💸 Withdraw DAO stake | - |
| `deactivate-company` | 🚫 Deactivate company | `company-id` |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-report` | 📄 Get report details | Report data |
| `get-company` | 🏢 Get company info | Company data |
| `get-dao-member` | 👤 Get member info | Member data |
| `get-next-report-id` | 🔢 Next report ID | `uint` |
| `get-total-staked` | 💰 Total staked amount | `uint` |
| `is-voting-active` | ⏰ Check if voting is active | `bool` |

## ⚙️ Configuration

### Constants

- **Voting Period**: 144 blocks (~24 hours)
- **Minimum Stake**: 1,000,000 microSTX (1 STX)
- **Reward Percentage**: 70% to reporter, 30% to DAO

## 🎯 Workflow

1. **Company Registration** 🏢
   - Companies stake STX to join platform
   - Becomes eligible to receive defect reports

2. **Defect Reporting** 📋
   - Users submit reports with evidence
   - Stake reward amount in escrow

3. **DAO Voting** 🗳️
   - DAO members vote within 144 blocks
   - Voting power based on stake amount

4. **Result Finalization** ✅
   - Approved: Reporter gets 70%, DAO gets 30%
   - Rejected: Reporter gets full refund

## 🔐 Security Features

- ✅ Stake-based voting prevents spam
- ✅ Time-locked voting periods
- ✅ Automatic reward distribution
- ✅ Company stake requirements
- ✅ Evidence hash validation

## 🧪 Testing

Run the test suite:
```bash
clarinet test
```

Check contract syntax:
```bash
clarinet check
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)

---

Built with ❤️ on Stacks blockchain 🚀
