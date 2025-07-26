

module escrow_factory::factory {
    use std::vector;
    use aptos_std::hash;
    use aptos_std::timestamp;
    use aptos_std::signer;
    use aptos_std::table::{Self as Table};
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;
    use aptos_framework::account;

    /* ------------------------------------------------------------ *
     *  Data types                                                  *
     * ------------------------------------------------------------ */

    /// Timelock parameters (seconds since Unix epoch)
    struct Timelock has store {
        withdrawTimestamp: u64,         // Timestamp when the depositor can withdraw
        publicWithDrawTimestamp: u64,   // Timestamp when the receiver can withdraw
        cancelTimestamp: u64,           // Timestamp when the depositor can cancel
        publicCancelTimestamp: u64,     // Timestamp when the receiver can cancel
        recoverTimestamp: u64,          // Timestamp when the depositor can recover
    }

    /// One hash-locked escrow
    struct Escrow has key {
        incentiveFee: u64,        // Incentive fee for the resolver
        deposit: u64,             // Amount of the asset being deposited
        depositor: address,         // address of the depositor
        receiver: address,          // address of the receiver
        hashlock: vector<u8>,       // sha3-256(secret)
        timelock: Timelock,
        source: address,
        vault_cap: account::SignerCapability
    }

    #[event]
    struct EscrowCreatedEvent has drop, store {
        vault_address: address,
        depositor: address,
        receiver: address,
        incentiveFee: u64,
        deposit: u64,
        hashlock: vector<u8>,
        withdrawTimestamp: u64,
        publicWithDrawTimestamp: u64,
        cancelTimestamp: u64,
        publicCancelTimestamp: u64,
        recoverTimestamp: u64,
    }


    public fun createEscrow<M: key>(account: &signer, 
            incentiveFeeAssetMetadata: object::Object<M>,
            incentiveFee: u64,
            depositAssetMetadata: object::Object<M>,
            deposit: u64, 
            orderHash: vector<u8>,
            hashlock: vector<u8>,
            receiver: address,
            withdrawTimestamp: u64,
            publicWithDrawTimestamp: u64,
            cancelTimestamp: u64,
            publicCancelTimestamp: u64,
            recoverTimestamp: u64
        ): address {
        let (vault_signer, cap) = account::create_resource_account(account, orderHash);
        let addr = signer::address_of(account);
        let escrow = Escrow {
            incentiveFee,
            deposit,
            hashlock: hashlock,
            depositor: addr,
            receiver,
            timelock: Timelock {
                withdrawTimestamp,
                publicWithDrawTimestamp,
                cancelTimestamp,
                publicCancelTimestamp,
                recoverTimestamp,
            },
            source: addr,
            vault_cap: cap,
        };
        move_to<Escrow>(
            &vault_signer,
            escrow
        );

        // Withdraw the incentive fee from the primary fungible store
        // and deposit it into the vault's primary store.
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(account, incentiveFeeAssetMetadata, incentiveFee);
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&vault_signer), incentiveFee_fa);

        // Withdraw the deposit from the primary fungible store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(account, depositAssetMetadata, deposit);
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&vault_signer), deposit_fa);

        0x1::event::emit(
            EscrowCreatedEvent {
                vault_address: signer::address_of(&vault_signer),
                depositor: addr,
                receiver,
                incentiveFee,
                deposit,
                hashlock,
                withdrawTimestamp,
                publicWithDrawTimestamp,
                cancelTimestamp,
                publicCancelTimestamp,
                recoverTimestamp,
            }
        );
        signer::address_of(&vault_signer)
    }



    // use std::error;
    // use std::signer;
    // use std::string;
    // use aptos_std::bcs;
    // use aptos_framework::event;
    // use aptos_framework::fungible_asset::FungibleAsset;

    // struct EscrowStore has key, store {
    //     inner: Table<address, Escrow>,
    // }

    // struct Escrow has key {
    //     // Used to incentivize resolvers to run actions.
    //     incentiveFee: FungibleAsset,
    //     // Token being escrowed.
    //     token : FungibleAsset,
    //     // Merkle root of the secrets.
    //     hashlog: vector<u8>,
    //     // Address of the depositor.
    //     depositor: address,
    //     // Address of the receiver. (this may be a receiver on another chain)
    //     receiver: address,

    //     // Timelock parameters.
    //     withdrawTimestamp: u64,
    //     publicWithDrawTimestamp: u64,
    //     cancelTimestamp: u64,
    //     publicCancelTimestamp: u64,
    //     recoverTimestamp: u64,
    // }

    // // TODO withdraw
    // // - Should use a merkle tree to recover the root 

    // // TODO cancel

    // // TODO recover
}