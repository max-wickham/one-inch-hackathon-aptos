
module escrow_factory::factory {
    use aptos_std::hash;
    use aptos_std::timestamp;
    use aptos_std::signer;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;
    use aptos_framework::account;

    /********************  Errors  *************************/
    const EINVALID_BALANCE: u64 = 0;
    const ERESOURCE_DOESNT_EXIST: u64 = 1;
    const EINVALID_SIGNER: u64 = 2;
    const ESTORE_NOT_PUBLISHED: u64 = 3;
    const EINVALID_TIMELOCK_STATE: u64 = 4;

    /* ------------------------------------------------------------ *
    *  Data types                                                  *
    * ------------------------------------------------------------ */

    /// Timelock parameters (seconds since Unix epoch)
    struct Timelock has store {
        withdrawTimestamp: u64, // Timestamp when the depositor can withdraw
        publicWithDrawTimestamp: u64, // Timestamp when the receiver can withdraw
        cancelTimestamp: u64, // Timestamp when the depositor can cancel
        publicCancelTimestamp: u64, // Timestamp when the receiver can cancel
        recoverTimestamp: u64 // Timestamp when the depositor can recover
    }

    /// One hash-locked escrow
    struct Escrow has key {
        incentiveFee: u64, // Incentive fee for the resolver
        deposit: u64, // Amount of the asset being deposited
        depositor: address, // address of the depositor
        receiver: address, // address of the receiver
        hashlock: vector<u8>, // sha3-256(secret)
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
        recoverTimestamp: u64
    }

    public fun createEscrow<M: key, N: key>(
        account: &signer,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>,
        incentiveFee: u64,
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
                recoverTimestamp
            },
            source: addr,
            vault_cap: cap
        };
        move_to<Escrow>(&vault_signer, escrow);

        // Withdraw the incentive fee from the primary fungible store
        // and deposit it into the vault's primary store.
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, incentiveFeeAssetMetadata, incentiveFee
            );
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(
            signer::address_of(&vault_signer), incentiveFee_fa
        );

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
                recoverTimestamp
            }
        );
        signer::address_of(&vault_signer)
    }

    public fun withdraw<M: key, N: key>(
        account: &signer,
        vault_address: address,
        secret: vector<u8>,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires Escrow {
        assert!(exists<Escrow>(vault_address), ERESOURCE_DOESNT_EXIST);
        let escrow = borrow_global<Escrow>(vault_address);
        let vault_signer = account::create_signer_with_capability(&escrow.vault_cap);

        // Check if the secret matches the hashlock
        assert!(hash::sha3_256(secret) == escrow.hashlock, 0x1);

        // Check the timelock state
        if (timestamp::now_seconds() >= escrow.timelock.publicWithDrawTimestamp) {
            assert!(
                timestamp::now_seconds() < escrow.timelock.cancelTimestamp,
                EINVALID_TIMELOCK_STATE
            );
        } else {
            assert!(timestamp::now_seconds() >= escrow.timelock.withdrawTimestamp, 0x2);
            assert!(signer::address_of(account) == escrow.receiver, EINVALID_SIGNER);
        };

        // Withdraw the incentive fee from the vault's primary store
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, incentiveFeeAssetMetadata, escrow.incentiveFee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentiveFee_fa);

        // Withdraw the deposit from the vault's primary store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, depositAssetMetadata, escrow.deposit
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(escrow.receiver, deposit_fa);
    }

    public fun cancel<M: key, N: key>(
        account: &signer,
        vault_address: address,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires Escrow {
        assert!(exists<Escrow>(vault_address), ERESOURCE_DOESNT_EXIST);
        let escrow = borrow_global<Escrow>(vault_address);
        let vault_signer = account::create_signer_with_capability(&escrow.vault_cap);

        // Check the timelock state
        if (timestamp::now_seconds() >= escrow.timelock.publicCancelTimestamp) {
            assert!(
                timestamp::now_seconds() < escrow.timelock.recoverTimestamp,
                EINVALID_TIMELOCK_STATE
            );
        } else {
            assert!(timestamp::now_seconds() >= escrow.timelock.cancelTimestamp, 0x2);
            assert!(signer::address_of(account) == escrow.depositor, EINVALID_SIGNER);
        };

        // Withdraw the incentive fee from the vault's primary store
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, incentiveFeeAssetMetadata, escrow.incentiveFee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentiveFee_fa);

        // Withdraw the deposit from the vault's primary store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, depositAssetMetadata, escrow.deposit
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(escrow.depositor, deposit_fa);
    }

    public fun recover<M: key, N: key>(
        account: &signer,
        vault_address: address,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires Escrow {
        assert!(exists<Escrow>(vault_address), ERESOURCE_DOESNT_EXIST);
        let escrow = borrow_global<Escrow>(vault_address);
        let vault_signer = account::create_signer_with_capability(&escrow.vault_cap);

        // Check the timelock state
        assert!(
            timestamp::now_seconds() >= escrow.timelock.recoverTimestamp,
            EINVALID_TIMELOCK_STATE
        );
        assert!(signer::address_of(account) == escrow.depositor, EINVALID_SIGNER);

        // Withdraw the incentive fee from the vault's primary store
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, incentiveFeeAssetMetadata, escrow.incentiveFee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentiveFee_fa);

        // Withdraw the deposit from the vault's primary store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &vault_signer, depositAssetMetadata, escrow.deposit
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(escrow.depositor, deposit_fa);
    }
}
