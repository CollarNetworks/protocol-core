# Some Diagrams

## ⚠️ The map is NOT the territory

These *may* be useful for high level overview or easier introduction to the codebase. However, such diagrams are always incomplete and inaccurate. 

### High level architecture

> Checked and tweaked manually

```mermaid
graph TB
    subgraph Protocol[Protocol]
        subgraph AssetPair[Asset Pair]
            Loans[Loans NFT]
            
            subgraph Positions[Collar Position]
                Taker[Collar Taker NFT]
                Provider[Collar Provider NFT]
            end
            
            RollsContract[Rolls]

            Oracle[Pair Price Oracle]
        end

        subgraph SingleAsset[Single Asset]
            EscrowNFT[Escrow Supplier NFT]
        end

        %% Configuration
        subgraph Config[Configuration]
            Hub[Config Hub]
        end


        Swap[Token Swapper]
    end


    %% External Systems
    subgraph External[External Dependencies]
        Sequencer[Sequencer Uptime]
        Chainlink[Chainlink Feeds]
        Router[Uniswap Router]
    end

    %% Relationships
    Loans --> Taker
    Loans --> EscrowNFT
    Loans --> RollsContract
    Loans --> Swap
    Taker --> Provider
    Taker --> Oracle
    Oracle --> Sequencer
    RollsContract --> Positions
    Swap --> Router
    Oracle --> Chainlink
    AssetPair --> Hub
    SingleAsset --> Hub

    %% Style
    classDef managedNft fill:#aaaaff,stroke:#333,stroke-width:2px
    classDef managed fill:#aaddff,stroke:#333,stroke-width:2px
    classDef unowned fill:#e6ffe6,stroke:#333
    classDef config fill:#ffe6cc,stroke:#333
    classDef chainlink fill:#ffffbb,stroke:#333

    class Loans,Taker,Provider,EscrowNFT managedNft
    class RollsContract managed
    class Oracle,Swap unowned
    class Hub,Admin config
    class Sequencer,Chainlink chainlink
```

### Example Call Flows

> All the below were not validated to be accurate, but seemed to be potentially useful as intro aids

#### `CollarTakerNFT.openPairedPosition`

```mermaid
sequenceDiagram
    participant User
    participant TakerNFT
    participant Oracle
    participant SequencerFeed
    participant Chainlink
    participant ProviderNFT

    User->>TakerNFT: openPairedPosition(takerLocked, providerNFT, offerId)
    activate TakerNFT

    TakerNFT->>Oracle: currentPrice()
    activate Oracle

    Oracle->>SequencerFeed: latestRoundData()
    activate SequencerFeed
    SequencerFeed-->>Oracle: status, startedAt, updatedAt
    deactivate SequencerFeed
    
    Note right of Oracle: Check if sequencer is live:<br/>status == 0 && <br/>uptime >= required

    Oracle->>Chainlink: prices
    activate Chainlink
    Chainlink-->>Oracle: prices
    deactivate Chainlink

    Oracle-->>TakerNFT: startPrice
    deactivate Oracle

    TakerNFT->>TakerNFT: calculateProviderLocked()
    Note right of TakerNFT: Calculate locked amounts<br/>based on LTV and strikes

    TakerNFT->>ProviderNFT: getOffer(offerId)
    activate ProviderNFT
    ProviderNFT-->>TakerNFT: offer
    deactivate ProviderNFT

    TakerNFT->>ProviderNFT: mintFromOffer(offerId, providerLocked)
    activate ProviderNFT
    Note right of ProviderNFT: Calculate protocol fee<br/>Check terms & amounts<br/>Pull assets
    ProviderNFT-->>TakerNFT: providerId
    deactivate ProviderNFT

    TakerNFT-->>User: takerId, providerId
    deactivate TakerNFT
```

#### `Rolls.executeRoll`

```mermaid
sequenceDiagram
    participant User
    participant LoansNFT
    participant Rolls
    participant TakerNFT
    participant Oracle
    participant SequencerFeed
    participant ProviderNFT

    Note over User,ProviderNFT: Preview Phase
    User->>Rolls: previewRoll(rollId, price)
    activate Rolls

    Rolls->>TakerNFT: getPosition(takerId)
    TakerNFT-->>Rolls: position

    Rolls->>TakerNFT: previewSettlement(position, price)
    TakerNFT-->>Rolls: takerSettled, providerGain

    Rolls->>ProviderNFT: protocolFee(newProviderLocked, duration)
    ProviderNFT-->>Rolls: fee, recipient

    Rolls-->>User: PreviewResults(toTaker, toProvider, rollFee, newAmounts)
    deactivate Rolls

    Note over User,ProviderNFT: Execution Phase
    User->>LoansNFT: rollLoan(loanId, rollOffer, minToUser, newEscrowId, newFee)
    activate LoansNFT

    LoansNFT->>Oracle: currentPrice()
    activate Oracle
    Oracle->>SequencerFeed: latestRoundData()
    SequencerFeed-->>Oracle: status, timestamp
    Note right of Oracle: Check sequencer uptime
    Oracle->>Chainlink: prices
    Chainlink-->>Oracle: prices
    Oracle-->>LoansNFT: price
    deactivate Oracle

    LoansNFT->>Rolls: executeRoll(rollId, minToUser)
    activate Rolls

    Rolls->>TakerNFT: cancelPairedPosition(takerId)
    activate TakerNFT
    Note right of TakerNFT: Burns both NFTs
    TakerNFT-->>Rolls: withdrawn
    deactivate TakerNFT

    Rolls->>ProviderNFT: createOffer(terms)
    activate ProviderNFT
    ProviderNFT-->>Rolls: newOfferId
    deactivate ProviderNFT

    Rolls->>TakerNFT: openPairedPosition(newLocked, provider, newOfferId)
    activate TakerNFT
    TakerNFT->>ProviderNFT: mintFromOffer(offerId, locked)
    TakerNFT-->>Rolls: newTakerId, newProviderId
    deactivate TakerNFT

    Rolls-->>LoansNFT: newTakerId, newProviderId, transfers
    deactivate Rolls

    LoansNFT-->>User: newLoanId, newAmount, toUser
    deactivate LoansNFT
```

#### `LoansNFT.openEscrowLoan`

```mermaid
sequenceDiagram
    participant User
    participant LoansNFT
    participant SwapperUniV3
    participant CollarTakerNFT
    participant CollarProviderNFT
    participant EscrowSupplierNFT

    Note over User,EscrowSupplierNFT: Opening Escrow Loan Flow
    User->>LoansNFT: openEscrowLoan(underlying, minLoan, swapParams, providerOffer, escrowOffer, escrowFee)
    activate LoansNFT
    
    LoansNFT->>EscrowSupplierNFT: startEscrow(escrowOfferId, underlying, escrowFee, nextTakerId)
    activate EscrowSupplierNFT
    Note right of EscrowSupplierNFT: Stores escrow position
    EscrowSupplierNFT-->>LoansNFT: escrowId
    deactivate EscrowSupplierNFT

    LoansNFT->>SwapperUniV3: swap(underlying, cashAsset, amount, minAmount)
    activate SwapperUniV3
    SwapperUniV3-->>LoansNFT: swappedCash
    deactivate SwapperUniV3

    LoansNFT->>CollarTakerNFT: openPairedPosition(takerLocked, providerNFT, offerId)
    activate CollarTakerNFT
    CollarTakerNFT->>CollarProviderNFT: mintFromOffer(offerId, providerLocked)
    CollarTakerNFT-->>LoansNFT: takerId, providerId
    deactivate CollarTakerNFT

    LoansNFT-->>User: loanId, providerId, loanAmount
    deactivate LoansNFT
```

#### `LoansNFT.rollLoan` (escrow based loan)

```mermaid
sequenceDiagram
    participant User
    participant LoansNFT
    participant Rolls
    participant CollarTakerNFT
    participant CollarProviderNFT
    participant EscrowSupplierNFT

    Note over User,EscrowSupplierNFT: Rolling Escrow Loan Flow
    User->>LoansNFT: rollLoan(loanId, rollOffer, minToUser, newEscrowOfferId, newEscrowFee)
    activate LoansNFT
    
    LoansNFT->>Rolls: executeRoll(rollId, minToUser)
    activate Rolls
    
    Rolls->>CollarTakerNFT: cancelPairedPosition(takerId)
    activate CollarTakerNFT
    CollarTakerNFT-->>Rolls: withdrawn cash
    deactivate CollarTakerNFT

    Rolls->>CollarTakerNFT: openPairedPosition(newTakerLocked, providerNFT, newOfferId)
    activate CollarTakerNFT
    CollarTakerNFT-->>Rolls: newTakerId, newProviderId
    deactivate CollarTakerNFT

    Rolls-->>LoansNFT: newTakerId, newProviderId, toTaker, toProvider
    deactivate Rolls

    LoansNFT->>EscrowSupplierNFT: switchEscrow(oldEscrowId, newOfferId, newFee, newLoanId)
    activate EscrowSupplierNFT
    EscrowSupplierNFT-->>LoansNFT: newEscrowId, feeRefund
    deactivate EscrowSupplierNFT

    LoansNFT-->>User: newLoanId, newLoanAmount, toUser
    deactivate LoansNFT
```
