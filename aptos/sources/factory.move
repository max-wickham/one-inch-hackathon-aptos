// Whitelist token... ?

module escrow_factory::order_factory {
    use aptos_std::hash;
    use std::bcs;
    use std::vector;
    use std::aptos_hash;
    use aptos_std::timestamp;
    use aptos_std::signer;
    use aptos_framework::fungible_asset::FungibleAsset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object;
    use aptos_framework::account;
    use std::debug;
    use aptos_framework::event;

    /********************  Errors  *************************/
    const EINVALID_BALANCE: u64 = 0;
    const ERESOURCE_DOESNT_EXIST: u64 = 1;
    const EINVALID_SIGNER: u64 = 2;
    const ESTORE_NOT_PUBLISHED: u64 = 3;
    const EINVALID_TIMELOCK_STATE: u64 = 4;
    const EINVALID_ASSET_TYPE: u64 = 5;
    const INVALID_HASH_TYPE: u64 = 6;

    /* ------------------------------------------------------------ *
    *  Data types                                                   *
    * ------------------------------------------------------------ */

    /// Timelock parameters (seconds since Unix epoch)
    struct Timelock has store, copy {
        withdraw_period_s: u64, // Timestamp when the depositor can withdraw
        public_withdraw_period_s: u64, // Timestamp when the receiver can withdraw
        cancel_period_s: u64, // Timestamp when the depositor can cancel
        public_cancel_period_s: u64 // Timestamp when the receiver can cancel
    }

    /// One hash-locked escrow. (Can be src or dst escrow.)
    struct Escrow has key {
        incentive_fee: u64, // Incentive fee for the resolver
        deposit: u64, // Amount of the asset being deposited
        depositor: address, // Address of the depositor
        receiver: address, // Address of the receiver
        hashlock: vector<u8>, // Keccak256 hash of the secret
        timelock: Timelock, // Timelock parameters
        start_timestamp: u64, // Timestamp when the escrow was created
        source: address, // Creator of the escrow
        escrow_cap: account::SignerCapability // Signer capability for the escrow
    }

    // FusionPlusOrder allowing for multiple escrows to be created to support multi-fill
    struct FusionPlusOrder has key {
        recover_incentive_fee: u64, // Total incentive fee to be paid to the resolver who calls recover
        recover_timestamp: u64, // Timestamp after which the order value can be recovered
        deposit_amount: u64, // Amount of the asset being deposited
        depositor: address, // Address of the depositor
        hashlock: vector<u8>, // Keaccak256 hash of the secret
        order_hash: vector<u8>, // Hash of the order parameters
        allow_multi_fill: bool, // Whether the order allows multiple escrows to be created
        whitelisted_addresses: vector<address>, // Addresses that can create escrows for this order
        timelock: Timelock, // Timelock parameters
        min_incentive_fee: u64, // Minimum incentive fee for escrow actions
        deposit_asset_type: address, // Address of the deposit asset type
        incentive_fee_asset_type: address, // Address of the incentive fee asset type
        order_cap: account::SignerCapability
    }

    #[event]
    public struct OrderCreatedEvent has drop, store {
        order_address: address,
        depositor: address,
        deposit_amount: u64,
        order_hash: vector<u8>
    }

    #[event]
    public struct EscrowCreatedEvent has drop, store {
        escrow_address: address,
        order_address: address,
        receiver: address,
        makeAmount: u64,
        incentive_fee: u64,
        escrow_hash: vector<u8>,
        proof: vector<vector<u8>>, // Merkle proof for the escrow
        leaf: vector<u8> // Merkle tree leaf
    }

    #[event]
    public struct EscrowDstCreatedEvent has drop, store {
        orderHash: vector<u8>,
        escrow_address: address,
        receiver: address,
        makeAmount: u64,
        incentive_fee: u64,
        escrow_hash: vector<u8>
    }

    public entry fun create_order<M: key>(
        relay: &signer,
        account: &signer,
        depositAssetMetadata: object::Object<M>, // Metadata of the deposit asset
        incentive_feeAssetMetadata: object::Object<M>, // Metadata of the incentive fee asset
        recover_incentive_fee: u64, // Total incentive fee to be paid to the resolver who calls recover
        recoverPeriod: u64, // Time period after which the order value can be recovered
        deposit_amount: u64, // Amount of the asset being deposited
        min_incentive_fee: u64, // Minimum incentive fee for escrow actions
        salt: vector<u8>, // Salt for the order hash
        hashlock: vector<u8>, // Keccak256 hash of the secret
        allow_multi_fill: bool, // Whether the order allows multiple escrows to be created
        whitelisted_addresses: vector<address>, // Addresses that can create escrows for this order
        withDrawPeriod: u64,
        publicWithDrawPeriod: u64,
        cancelPeriod: u64,
        publicCancelPeriod: u64,
    ) {
        // If the merkle root is not empty, we allow multi-fill
        let incentive_feeAssetMetadataHash =
            aptos_hash::keccak256(bcs::to_bytes(&incentive_feeAssetMetadata));
        let order_hash =
            aptos_hash::keccak256(
                bcs::to_bytes(
                    &vector[
                        bcs::to_bytes(&depositAssetMetadata), bcs::to_bytes(
                            &deposit_amount
                        ), bcs::to_bytes(&min_incentive_fee), bcs::to_bytes(&salt), bcs::to_bytes(
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
            order_cap: cap,
            deposit_amount,
            depositor: addr,
            hashlock,
            order_hash: order_hash,
            recover_incentive_fee,
            min_incentive_fee,
            incentive_fee_asset_type: object::object_address(&incentive_feeAssetMetadata),
            deposit_asset_type: object::object_address(&depositAssetMetadata),
            recover_timestamp: timestamp::now_seconds() + recoverPeriod,
            timelock: Timelock {
                withdraw_period_s: withDrawPeriod,
                public_withdraw_period_s: publicWithDrawPeriod,
                cancel_period_s: cancelPeriod,
                public_cancel_period_s: publicCancelPeriod
            },
            allow_multi_fill,
            whitelisted_addresses,
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
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                relay, incentive_feeAssetMetadata, recover_incentive_fee
            );

        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(
            signer::address_of(&vault_signer), incentive_fee_fa
        );

        let order_address = signer::address_of(&vault_signer);
        event::emit(
            OrderCreatedEvent {
                order_address: order_address,
                depositor: addr,
                deposit_amount,
                order_hash            
            }
        );
        debug::print(&signer::address_of(&vault_signer));
    }

    public entry fun create_escrow_src<M: key, N: key>(
        account: &signer,
        order_address: address,
        incentive_feeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>,
        makeAmount: u64,
        incentive_fee: u64,
        receiver: address,
        salt: vector<u8>,
        leaf: vector<u8>, // Merkle tree leaf
        proof: vector<vector<u8>>, // Merkle tree proof
        directions: vector<bool>,
    ) acquires FusionPlusOrder {
        // Find the order and create an escrow signer for it
        assert!(exists<FusionPlusOrder>(order_address), ERESOURCE_DOESNT_EXIST);
        let order = borrow_global<FusionPlusOrder>(order_address);
        let order_signer = account::create_signer_with_capability(&order.order_cap);
        let escrow_hash =
            aptos_hash::keccak256(
                bcs::to_bytes(
                    &vector[bcs::to_bytes(&order.order_hash), bcs::to_bytes(&salt)]
                )
            );
        let (escrow_signer, cap) = account::create_resource_account(
            account, escrow_hash
        );
        let addr = signer::address_of(account);

        // Ensure that the incentive fee is greater than the minimum incentive fee
        assert!(incentive_fee > order.min_incentive_fee, EINVALID_BALANCE);

        // TODO set deposit amount to the order balance
        // Ensure that the make amount is less than or equal to the deposit amount
        assert!(makeAmount <= order.deposit_amount, EINVALID_BALANCE);

        // If multi fill is not allowed, ensure that the make amount is equal to the deposit amount
        let hashlock;
        if (!order.allow_multi_fill) {
            // Ensure the leaf is length 0
            assert!(vector::length(&leaf) == 0, INVALID_HASH_TYPE);
            // Ensure the proof is length 0
            assert!(vector::length(&proof) == 0, INVALID_HASH_TYPE);
            // Ensure that the make amount is equal to the deposit amount
            assert!(makeAmount == order.deposit_amount, EINVALID_BALANCE);
            hashlock = order.hashlock;
        } else {
            assert!(validate_merkle_proof(
                order.hashlock, leaf, proof, directions
            ), 8);
            hashlock = leaf;
        };

        // Ensure that the receiver is whitelisted if whitelist exists
        if (vector::length(&order.whitelisted_addresses) > 0) {
            // Ensure that the address is whitelisted
            assert!(
                vector::contains(&order.whitelisted_addresses, &addr),
                EINVALID_SIGNER
            );
        };

        // Verify that the asset types match the order
        assert!(
            object::object_address(&incentive_feeAssetMetadata)
                == order.incentive_fee_asset_type,
            EINVALID_ASSET_TYPE
        );
        assert!(
            object::object_address(&depositAssetMetadata) == order.deposit_asset_type,
            EINVALID_ASSET_TYPE
        );

        // Ensure that we are not passed the order recover timestamp
        assert!(
            timestamp::now_seconds() < order.recover_timestamp,
            EINVALID_TIMELOCK_STATE
        );
        debug::print(&b"Creating escrow with hashlock: ");
        // Create the escrow object
        let escrow = Escrow {
            incentive_fee,
            deposit: makeAmount,
            hashlock: hashlock,
            depositor: order.depositor,
            // TODO !!!!!!!!!!!!!!!!!!!!!!11
            // receiver: receiver,
            receiver: signer::address_of(account),
            start_timestamp: timestamp::now_seconds(),
            timelock: order.timelock,
            source: signer::address_of(&order_signer),
            escrow_cap: cap
        };
        move_to<Escrow>(&escrow_signer, escrow);

        // Withdraw the incentive fee from the primary fungible store
        // and deposit it into the escrow's primary store.
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, incentive_feeAssetMetadata, incentive_fee
            );
        // … and push them into the escrow primary store
        primary_fungible_store::deposit(
            signer::address_of(&escrow_signer), incentive_fee_fa
        );

        // Withdraw the make amount from the primary fungible store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &order_signer, depositAssetMetadata, makeAmount
            );
        // and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&escrow_signer), deposit_fa);

        // If the balance of the deposit asset in the order is 0 return the recover incentive to the creator
        let order_balance =
            primary_fungible_store::balance(
                signer::address_of(&order_signer), depositAssetMetadata
            );
        if (order_balance == 0) {
            // Withdraw the recover incentive fee from the escrow's primary store
            let recover_incentive_fa: FungibleAsset =
                primary_fungible_store::withdraw(
                    &order_signer,
                    incentive_feeAssetMetadata,
                    order.recover_incentive_fee
                );
            // … and push them into the primary store of the order creator
            primary_fungible_store::deposit(receiver, recover_incentive_fa);
        };

        let escrow_address = signer::address_of(&escrow_signer);
        event::emit(
            EscrowCreatedEvent {
                escrow_address,
                order_address,
                receiver,
                makeAmount,
                incentive_fee,
                escrow_hash,
                proof: proof,
                leaf: hashlock
            }
        );

        debug::print(&escrow_address);
    }

    public entry fun create_escrow_dst<M: key, N: key>(
        account: &signer,
        order_hash: vector<u8>,
        receiver: address,
        incentive_feeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>,
        deposit_amount: u64,
        incentive_fee: u64,
        salt: vector<u8>,
        hashlock: vector<u8>, // Keccak256 hash of the secret
        withDrawPeriod: u64,
        publicWithDrawPeriod: u64,
        cancelPeriod: u64,
        publicCancelPeriod: u64
    ) {
        let escrow_hash =
            aptos_hash::keccak256(
                bcs::to_bytes(
                    &vector[bcs::to_bytes(&order_hash), bcs::to_bytes(&salt)]
                )
            );
        let (escrow_signer, cap) = account::create_resource_account(
            account, escrow_hash
        );
        let addr = signer::address_of(account);

        // Deposit the incentive fee into the escrow primary store
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, incentive_feeAssetMetadata, incentive_fee
            );
        // … and push them into the escrow primary store
        primary_fungible_store::deposit(
            signer::address_of(&escrow_signer), incentive_fee_fa
        );
        // Withdraw the deposit from the primary fungible store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                account, depositAssetMetadata, deposit_amount
            );
        // … and push them into the vault’s primary store
        primary_fungible_store::deposit(signer::address_of(&escrow_signer), deposit_fa);

        // Create the escrow object
        let escrow = Escrow {
            incentive_fee,
            deposit: deposit_amount,
            hashlock,
            depositor: addr,
            receiver: receiver,
            start_timestamp: timestamp::now_seconds(),
            timelock: Timelock {
                withdraw_period_s: withDrawPeriod,
                public_withdraw_period_s: publicWithDrawPeriod,
                cancel_period_s: cancelPeriod,
                public_cancel_period_s: publicCancelPeriod
            },
            source: addr,
            escrow_cap: cap
        };

        event::emit(
            EscrowDstCreatedEvent {
                orderHash: order_hash,
                escrow_address: signer::address_of(&escrow_signer),
                receiver,
                makeAmount: deposit_amount,
                incentive_fee,
                escrow_hash
            }
        );

        move_to<Escrow>(&escrow_signer, escrow);
    }

    public entry fun recover<M: key, N: key>(
        account: &signer,
        order_address: address,
        incentive_feeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires FusionPlusOrder {
        assert!(exists<FusionPlusOrder>(order_address), ERESOURCE_DOESNT_EXIST);
        let order = borrow_global<FusionPlusOrder>(order_address);
        let order_signer = account::create_signer_with_capability(&order.order_cap);

        // Check if the recover period has passed
        assert!(
            timestamp::now_seconds() >= order.recover_timestamp,
            EINVALID_TIMELOCK_STATE
        );

        // Verify that the asset types match the order
        assert!(
            object::object_address(&incentive_feeAssetMetadata)
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
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &order_signer, incentive_feeAssetMetadata, order.recover_incentive_fee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentive_fee_fa);
    }

    public entry fun withdraw<M: key, N: key>(
        account: &signer,
        vault_address: address,
        secret: vector<u8>,
        incentive_feeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires Escrow {
        assert!(exists<Escrow>(vault_address), ERESOURCE_DOESNT_EXIST);
        let escrow = borrow_global<Escrow>(vault_address);
        let escrow_signer = account::create_signer_with_capability(&escrow.escrow_cap);

        // Check if the secret matches the hashlock
        assert!(aptos_hash::keccak256(secret) == escrow.hashlock, 0x1);

        // Check the timelock state
        if (timestamp::now_seconds()
            >= escrow.start_timestamp + escrow.timelock.public_withdraw_period_s) {
            assert!(
                timestamp::now_seconds()
                    < escrow.start_timestamp + escrow.timelock.cancel_period_s,
                EINVALID_TIMELOCK_STATE
            );
        } else {
            assert!(
                timestamp::now_seconds()
                    >= escrow.start_timestamp + escrow.timelock.withdraw_period_s,
                EINVALID_TIMELOCK_STATE
            );
            assert!(
                signer::address_of(account) == escrow.receiver || 
                signer::address_of(account) == escrow.depositor,
                EINVALID_SIGNER);
        };

        // Withdraw the incentive fee from the vault's primary store
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &escrow_signer, incentive_feeAssetMetadata, escrow.incentive_fee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentive_fee_fa);

        // Withdraw the deposit from the vault's primary store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &escrow_signer, depositAssetMetadata, escrow.deposit
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(escrow.receiver, deposit_fa);
    }

    public entry fun cancel<M: key, N: key>(
        account: &signer,
        vault_address: address,
        incentive_feeAssetMetadata: object::Object<M>,
        depositAssetMetadata: object::Object<N>
    ) acquires Escrow {
        assert!(exists<Escrow>(vault_address), ERESOURCE_DOESNT_EXIST);
        let escrow = borrow_global<Escrow>(vault_address);
        let escrow_signer = account::create_signer_with_capability(&escrow.escrow_cap);

        // Check the timelock state
        if (timestamp::now_seconds()
            < escrow.start_timestamp + escrow.timelock.public_cancel_period_s) {
            assert!(
                timestamp::now_seconds()
                    >= escrow.start_timestamp + escrow.timelock.cancel_period_s,
                EINVALID_TIMELOCK_STATE
            );
            assert!(signer::address_of(account) == escrow.depositor, EINVALID_SIGNER);
        };

        // Withdraw the incentive fee from the vault's primary store
        let incentive_fee_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &escrow_signer, incentive_feeAssetMetadata, escrow.incentive_fee
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(signer::address_of(account), incentive_fee_fa);

        // Withdraw the deposit from the vault's primary store
        let deposit_fa: FungibleAsset =
            primary_fungible_store::withdraw(
                &escrow_signer, depositAssetMetadata, escrow.deposit
            );
        // … and push them into the primary store of the account
        primary_fungible_store::deposit(escrow.depositor, deposit_fa);
    }

    fun validate_merkle_proof(
        root: vector<u8>,
        leaf: vector<u8>,
        proof: vector<vector<u8>>,
        directions: vector<bool>
    ): bool {
        let result: vector<vector<u8>> = vector::empty();
        let hash = leaf;
        result.push_back(hash);
        while (vector::length(&proof) > 0) {
            let node = vector::pop_back(&mut proof);
            let isRight = vector::pop_back(&mut directions);
            result.push_back(node);
            if (isRight) {
                let combined = hash;
                vector::append(&mut combined, node);
                hash = aptos_hash::keccak256(combined);
            } else {
                let combined = node;
                vector::append(&mut combined, hash);
                hash = aptos_hash::keccak256(combined);
            };
            result.push_back(hash);
        };
        root == hash
    }
}
