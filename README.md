# Real-World Assets (RWAs)

**IMPORTANT:** *This repo is a work in progress, and contracts have not been audited. Use at your own risk.*

<p align="center">
  <img src="./img/rwas.png" width="300" alt="tokenized-assets">
</p>

## Table of Contents

- [The Methodology](#the-methodology)
  - [Examples that don't make sense](#examples-that-dont-make-sense)
  - [Examples that would make sense](#examples-that-would-make-sense)
- [The Three Examples in This Repo](#the-three-examples-in-this-repo)
  - [dTSLA.sol](#dtslasol)
    - [V1](#v1)
    - [V2 (not implemented)](#v2-not-implemented)
  - [sTSLA.sol](#stslasol)
  - [BridgedWETH.sol](#bridgedwethsol)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [Details on the Four Examples](#details-on-the-four-examples)
- [Currently Live Examples of Tokenized RWAs](#currently-live-examples-of-tokenized-rwas)
- [What Does This Unlock?](#what-does-this-unlock)
- [Disclaimer](#disclaimer)

## The Methodology

We can tokenize real-world assets by combining the following traits:

- **Asset location**: On or Off Chain Asset Represented (`AOn`, `AOff`)
- **Collateral location**: On or Off-Chain Collateral (`COn`, `COff`)
- **Backing type**: Direct backing or Indirect (synthetic) (`DB`, `SB`)

This results in 8 different types of RWAs.

<details>
<summary>Examples of the 8 assets</summary>

- `AOnCOnDB`: On-chain asset, on-chain collateral, direct backing (e.g., WETH)
- `AOnCOnSB`: On-chain asset, on-chain collateral, synthetic backing (e.g., WBTC)
- `AOnCOffDB`: On-chain asset, off-chain collateral, direct backing
- `AOnCOffSB`: On-chain asset, off-chain collateral, synthetic backing
- `AOffCOnDB`: Off-chain asset, on-chain collateral, direct backing
- `AOffCOnSB`: Off-chain asset, on-chain collateral, synthetic backing (e.g., DAI)
- `AOffCOffDB`: Off-chain asset, off-chain collateral, direct backing (e.g., USDC)
- `AOffCOffSB`: Off-chain asset, off-chain collateral, synthetic backing (e.g., USDT)

</details>

### Examples that don't make sense

- **Directly Backed On-Chain Asset Representation with Off-Chain Collateral**: Representing ETH on-chain with off-chain ETH ETF collateral is illogical.
- **Synthetic On-Chain Asset Representation with Off-Chain Collateral**: Backing on-chain assets like MSFT shares with off-chain collateral is impractical.
- **Directly Backed Off-Chain Asset Representation with On-Chain Collateral**: Direct backing of off-chain assets with on-chain collateral is inherently synthetic.

### Examples that would make sense

- **Synthetic Off-Chain Asset Representation with Off-Chain Collateral**: A synthetic index fund share backed by various stocks.

## The Three Examples in This Repo

In this repo, we will cover:

1. `CrossChainWETH.sol`: Cross-Chain WETH with On-Chain collateral, Directly Backed (`AOnCOnDB`)
2. `sTSLA.sol`: TSLA Share with On-Chain collateral, Synthetic (`AOffCOnSB`)
3. `dTSLA.sol`: TSLA Share with Off-Chain collateral, Directly Backed (`AOffCOffDB`)

### dTSLA.sol

#### V1

- Only the owner can mint `dTSLA`
- Anyone can redeem `dTSLA` for `USDC` or other stablecoins
- Chainlink functions trigger a `TSLA` sell for USDC, then send it to the contract
- Users call `finishRedeem` to get their `USDC`

#### V2 (not implemented)

- Users send USDC to `dTSLA.sol` via `sendMintRequest`
- USDC is converted to TSLA shares through Chainlink Functions
- Users call `finishMint` to withdraw their minted `dTSLA` tokens

### sTSLA.sol

A synthetic TSLA token using a Chainlink price feed to govern the token's price. Learn more at the [Cyfrin Updraft](https://updraft.cyfrin.io/) curriculum.

### BridgedWETH.sol

Token transfers using the CCIP protocol:

1. WETH contract on "home" chain
2. BridgedWETH contract on other chains
3. Chainlink CCIP Sender & Receiver Contract

## Getting Started

### Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- [foundry](https://getfoundry.sh/)
- [node](https://nodejs.org/en/download/)
- [npm](https://www.npmjs.com/get-npm)
- [deno](https://docs.deno.com/runtime/manual/getting_started/installation)

### Installation

1. Clone the repo, navigate to the directory, and install dependencies with `make`:

   ```sh
   git clone https://github.com/sohammirajkar/Real-world-asset.git
   cd Real-world-asset
   make
