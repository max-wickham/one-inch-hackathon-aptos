module escrow_factory::factory {
    use aptos_std::hash;
    use std::bcs;
    use std::aptos_hash;
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
    const EINVALID_ASSET_TYPE: u64 = 5;

    /* ------------------------------------------------------------ *
    *  Data types                                                  *
    * ------------------------------------------------------------ */

    /// Timelock parameters (seconds since Unix epoch)
    struct Timelock has store, copy {
        withdrawTimestamp: u64, // Timestamp when the depositor can withdraw
        publicWithDrawTimestamp: u64, // Timestamp when the receiver can withdraw
        cancelTimestamp: u64, // Timestamp when the depositor can cancel
        publicCancelTimestamp: u64 // Timestamp when the receiver can cancel
    }

    /// One hash-locked escrow
    struct Escrow has key {
        incentiveFee: u64, // Incentive fee for the resolver
        deposit: u64, // Amount of the asset being deposited
        depositor: address, // address of the depositor
        receiver: address, // address of the receiver
        hashlock: vector<u8>, // sha3-256(secret)
        timelock: Timelock,
        startTimestamp: u64, // Timestamp when the escrow was created
        source: address,
        vault_cap: account::SignerCapability
    }

    struct FusionPlusOrder has key {
        // Stores the deposit amount
        vault_cap: account::SignerCapability,
        recoverIncentiveFee: u64, // Amount of the asset to be recovered
        recoverTimestamp: u64, // Timestamp when the order can be recovered
        deposit_amount: u64, // Amount of the asset being deposited
        depositor: address, // address of the depositor
        hashlock: vector<u8>, // sha3-256(secret)
        order_hash: vector<u8>, // hash of the order
        incentive_fee_asset_type: address, // Address of the incentive fee asset type
        deposit_asset_type: address, // Address of the deposit asset type
        timelock: Timelock, // Timelock parameters
        minIncentiveFee: u64 // Minimum incentive fee for the resolver
    }

    public fun createOrder<M: key>(
        account: &signer,
        depositAssetMetadata: object::Object<M>,
        incentiveFeeAssetMetadata: object::Object<M>,
        recoverIncentiveFee: u64,
        recoverPeriod: u64,
        deposit_amount: u64,
        minIncentiveFee: u64,
        salt: vector<u8>,
        hashlock: vector<u8>,
        withDrawPeriod: u64,
        publicWithDrawPeriod: u64,
        cancelPeriod: u64,
        publicCancelPeriod: u64
    ): address {
        let incentiveFeeAssetMetadataHash =
            aptos_hash::keccak256(bcs::to_bytes(&incentiveFeeAssetMetadata));
        let order_hash =
            aptos_hash::keccak256(
                bcs::to_bytes(
                    &vector[
                        bcs::to_bytes(&depositAssetMetadata), bcs::to_bytes(
                            &deposit_amount
                        ), bcs::to_bytes(&minIncentiveFee), bcs::to_bytes(&salt), bcs::to_bytes(
                            &hashlock
                        ), bcs::to_bytes(&withDrawPeriod), bcs::to_bytes(
                            &publicWithDrawPeriod
                        ), bcs::to_bytes(&cancelPeriod), bcs::to_bytes(
                            &publicCancelPeriod
                        )
                    ]
                )
            );

        let (vault_signer, cap) = account::create_resource_account(account, order_hash);
        let addr = signer::address_of(account);
        let order = FusionPlusOrder {
            vault_cap: cap,
            deposit_amount,
            depositor: addr,
            hashlock,
            order_hash: order_hash,
            recoverIncentiveFee,
            minIncentiveFee,
            incentive_fee_asset_type: object::object_address(&incentiveFeeAssetMetadata),
            deposit_asset_type: object::object_address(&depositAssetMetadata),
            recoverTimestamp: timestamp::now_seconds() + recoverPeriod,
            timelock: Timelock {
                withdrawTimestamp: withDrawPeriod,
                publicWithDrawTimestamp: publicWithDrawPeriod,
                cancelTimestamp: cancelPeriod,
                publicCancelTimestamp: publicCancelPeriod
            }
        };
        move_to<FusionPlusOrder>(&vault_signer, order);

        // Withdraw the deposit from the primary fungible store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, depositAssetMetadata, deposit_amount
            );
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&vault_signer), deposit_fa);

        // Deposit the incentive fee into the vault's primary store
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, incentiveFeeAssetMetadata, recoverIncentiveFee
            );
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(
            signer::address_of(&vault_signer), incentiveFee_fa
        );

        signer::address_of(&vault_signer)
    }

    public fun escrow_exists(vault_address: address): bool {
        exists<Escrow>(vault_address)
    }

    public fun createEscrow<M: key, N: key>(
        account: &signer,
        order_address: address,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>,
        makeAmount: u64,
        incentiveFee: u64,
        receiver: address
    ): address acquires FusionPlusOrder {
        assert!(exists<FusionPlusOrder>(order_address), ERESOURCE_DOESNT_EXIST);
        let order = borrow_global<FusionPlusOrder>(order_address);
        let order_signer = account::create_signer_with_capability(&order.vault_cap);

        let (vault_signer, cap) =
            account::create_resource_account(account, order.order_hash);
        let addr = signer::address_of(account);

        assert!(incentiveFee > order.minIncentiveFee, EINVALID_BALANCE);
        assert!(makeAmount <= order.deposit_amount, EINVALID_BALANCE);

        // Verify that the asset types match the order
        assert!(
            object::object_address(&incentiveFeeAssetMetadata)
                == order.incentive_fee_asset_type,
            EINVALID_ASSET_TYPE
        );
        assert!(
            object::object_address(&depositAssetMetadata) == order.deposit_asset_type,
            EINVALID_ASSET_TYPE
        );

        let escrow = Escrow {
            incentiveFee,
            deposit: makeAmount,
            hashlock: order.hashlock,
            depositor: order.depositor,
            receiver: signer::address_of(account),
            startTimestamp: timestamp::now_seconds(),
            timelock: order.timelock,
            source: signer::address_of(&order_signer),
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
            primary_fungible_store::withdraw(
                &order_signer, depositAssetMetadata, makeAmount
            );
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&vault_signer), deposit_fa);

        signer::address_of(&vault_signer)
    }

    public fun recover<M: key, N: key>(
        account: &signer,
        order_address: address,
        incentiveFeeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires FusionPlusOrder {
        assert!(exists<FusionPlusOrder>(order_address), ERESOURCE_DOESNT_EXIST);
        let order = borrow_global<FusionPlusOrder>(order_address);
        let order_signer = account::create_signer_with_capability(&order.vault_cap);

        // Check if the recover period has passed
        assert!(
            timestamp::now_seconds() >= order.recoverTimestamp,
            EINVALID_TIMELOCK_STATE
        );

        // Verify that the asset types match the order
        assert!(
            object::object_address(&incentiveFeeAssetMetadata)
                == order.incentive_fee_asset_type,
            EINVALID_ASSET_TYPE
        );
        assert!(
            object::object_address(&depositAssetMetadata) == order.deposit_asset_type,
            EINVALID_ASSET_TYPE
        );

        // Withdraw the deposit from the vault's primary store
        let balance =
            primary_fungible_store::balance(
                signer::address_of(&order_signer), depositAssetMetadata
            );
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &order_signer, depositAssetMetadata, balance
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(order.depositor, deposit_fa);

        // Withdraw the incentive fee from the vault's primary store
        let incentiveFee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &order_signer, incentiveFeeAssetMetadata, order.recoverIncentiveFee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentiveFee_fa);
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
        assert!(aptos_hash::keccak256(secret) == escrow.hashlock, 0x1);

        // Check the timelock state
        if (timestamp::now_seconds()
            >= escrow.startTimestamp + escrow.timelock.publicWithDrawTimestamp) {
            assert!(
                timestamp::now_seconds()
                    < escrow.startTimestamp + escrow.timelock.cancelTimestamp,
                EINVALID_TIMELOCK_STATE
            );
        } else {
            assert!(
                timestamp::now_seconds()
                    >= escrow.startTimestamp + escrow.timelock.withdrawTimestamp,
                0x2
            );
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
        if (timestamp::now_seconds()
            < escrow.startTimestamp + escrow.timelock.publicCancelTimestamp) {
            assert!(
                timestamp::now_seconds()
                    >= escrow.startTimestamp + escrow.timelock.cancelTimestamp,
            EINVALID_TIMELOCK_STATE
            );
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
}
