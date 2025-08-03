#[test_only]
module escrow_factory::order_factory_tests {
    use std::string;
    use std::vector;
    use std::option;
    use aptos_std::timestamp;
    use aptos_std::signer;
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, MintRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use escrow_factory::order_factory;
    use aptos_std::aptos_hash;
    use std::debug;

    // Test constants
    const INCENTIVE_FEE: u64 = 100;
    const DEPOSIT_AMOUNT: u64 = 1000;
    const MIN_INCENTIVE_FEE: u64 = 50;
    const RECOVER_INCENTIVE_FEE: u64 = 75;
    const SECRET: vector<u8> = b"test_secret_123";
    const SALT: vector<u8> = b"test_salt_456";

    // Time periods (in seconds)
    const WITHDRAW_PERIOD: u64 = 100;
    const PUBLIC_WITHDRAW_PERIOD: u64 = 200;
    const CANCEL_PERIOD: u64 = 300;
    const PUBLIC_CANCEL_PERIOD: u64 = 400;
    const RECOVER_PERIOD: u64 = 500;

    // Global storage for mint references
    struct TestTokenRefs has key {
        incentive_mint_ref: MintRef,
        incentive_burn_ref: BurnRef,
        incentive_metadata: Object<Metadata>,
        deposit_mint_ref: MintRef,
        deposit_burn_ref: BurnRef,
        deposit_metadata: Object<Metadata>
    }

    #[test_only]
    fun create_test_tokens(creator: &signer): (Object<Metadata>, Object<Metadata>) {
        // Create incentive token
        let incentive_constructor_ref =
            &object::create_named_object(creator, b"IncentiveCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            incentive_constructor_ref,
            option::none(),
            string::utf8(b"Incentive Coin"),
            string::utf8(b"INC"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );

        let incentive_metadata =
            object::object_from_constructor_ref(incentive_constructor_ref);
        let incentive_mint_ref =
            fungible_asset::generate_mint_ref(incentive_constructor_ref);
        let incentive_burn_ref =
            fungible_asset::generate_burn_ref(incentive_constructor_ref);

        // Create deposit token
        let deposit_constructor_ref =
            &object::create_named_object(creator, b"DepositCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            deposit_constructor_ref,
            option::none(),
            string::utf8(b"Deposit Coin"),
            string::utf8(b"DEP"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );

        let deposit_metadata =
            object::object_from_constructor_ref(deposit_constructor_ref);
        let deposit_mint_ref = fungible_asset::generate_mint_ref(deposit_constructor_ref);
        let deposit_burn_ref = fungible_asset::generate_burn_ref(deposit_constructor_ref);

        // Store both token references in a single resource
        let token_refs = TestTokenRefs {
            incentive_mint_ref,
            incentive_burn_ref,
            incentive_metadata,
            deposit_mint_ref,
            deposit_burn_ref,
            deposit_metadata
        };
        move_to(creator, token_refs);

        (incentive_metadata, deposit_metadata)
    }

    #[test_only]
    fun mint_test_tokens(creator: &signer, to: address, amount: u64) acquires TestTokenRefs {
        let token_refs = borrow_global<TestTokenRefs>(signer::address_of(creator));
        let fa = fungible_asset::mint(&token_refs.incentive_mint_ref, amount);
        primary_fungible_store::deposit(to, fa);
        let fa = fungible_asset::mint(&token_refs.deposit_mint_ref, amount);
        primary_fungible_store::deposit(to, fa);
    }

    #[test_only]
    fun setup_test_environment(): (signer, signer, signer, signer, Object<Metadata>, Object<Metadata>) acquires TestTokenRefs {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        timestamp::update_global_time_for_test_secs(1000);

        let creator = account::create_account_for_test(@0x123);
        let relay = account::create_account_for_test(@0x124);
        let depositor = account::create_account_for_test(@0x456);
        let receiver = account::create_account_for_test(@0x789);

        // Create two different test tokens with unique names
        let (incentive_metadata, deposit_metadata) = create_test_tokens(&creator);

        // Mint tokens to all parties
        mint_test_tokens(&creator, @0x124, 10000); // relay
        mint_test_tokens(&creator, @0x456, 10000); // depositor
        mint_test_tokens(&creator, @0x789, 10000); // receiver

        (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata)
    }

    #[test_only]
    fun get_order_address(
        depositor: &signer,
        deposit_metadata: Object<Metadata>,
        deposit_amount: u64,
        min_incentive_fee: u64,
        salt: vector<u8>,
        hashlock: vector<u8>,
        withdraw_period: u64,
        public_withdraw_period: u64,
        cancel_period: u64,
        public_cancel_period: u64
    ): vector<u8> {
        let order_hash =
            aptos_hash::keccak256(
                bcs::to_bytes(
                    &vector[
                        bcs::to_bytes(&deposit_metadata),
                        bcs::to_bytes(&deposit_amount),
                        bcs::to_bytes(&min_incentive_fee),
                        bcs::to_bytes(&salt),
                        bcs::to_bytes(&hashlock),
                        bcs::to_bytes(&withdraw_period),
                        bcs::to_bytes(&public_withdraw_period),
                        bcs::to_bytes(&cancel_period),
                        bcs::to_bytes(&public_cancel_period)
                    ]
                )
            );
        order_hash
    }

    #[test]
    fun test_create_order_success() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let relay_initial_incentive = primary_fungible_store::balance(@0x124, incentive_metadata);

        // Create order
        order_factory::create_order(
            &relay,
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            true, // allow_multi_fill
            vector::empty<address>(), // whitelisted_addresses
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Verify depositor's deposit balance decreased
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(depositor_final_deposit == depositor_initial_deposit - DEPOSIT_AMOUNT, 1);

        // Verify relay's incentive balance decreased
        let relay_final_incentive = primary_fungible_store::balance(@0x124, incentive_metadata);
        assert!(relay_final_incentive == relay_initial_incentive - RECOVER_INCENTIVE_FEE, 2);
    }

    #[test]
    fun test_create_escrow_src_success() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // First create order
        order_factory::create_order(
            &relay,
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            false, // allow_multi_fill = false for this test
            vector::empty<address>(),
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate order address
        let order_hash = get_order_address(
            &depositor,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );
        let order_address = account::create_resource_address(&signer::address_of(&depositor), order_hash);

        let receiver_initial_incentive = primary_fungible_store::balance(@0x789, incentive_metadata);

        // Create escrow src
        order_factory::create_escrow_src(
            &receiver,
            order_address,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT, // makeAmount
            INCENTIVE_FEE,
            signer::address_of(&receiver),
            b"escrow_salt",
            vector::empty<u8>(), // leaf (empty for non-multi-fill)
            vector::empty<vector<u8>>(), // proof
            vector::empty<bool>() // directions
        );

        // Verify receiver's incentive balance decreased
        let receiver_final_incentive = primary_fungible_store::balance(@0x789, incentive_metadata);
        assert!(receiver_final_incentive == receiver_initial_incentive - INCENTIVE_FEE + RECOVER_INCENTIVE_FEE, 1);
    }

    #[test]
    fun test_create_escrow_dst_success() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"test_order_hash";

        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let depositor_initial_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);

        // Create destination escrow
        order_factory::create_escrow_dst(
            &depositor,
            order_hash,
            signer::address_of(&receiver),
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Verify depositor's balances decreased
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let depositor_final_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);

        assert!(depositor_final_deposit == depositor_initial_deposit - DEPOSIT_AMOUNT, 1);
        assert!(depositor_final_incentive == depositor_initial_incentive - INCENTIVE_FEE, 2);
    }

    #[test]
    fun test_withdraw_with_valid_secret() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"test_order_hash";

        // Create destination escrow
        order_factory::create_escrow_dst(
            &depositor,
            order_hash,
            signer::address_of(&receiver),
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate escrow address
        let escrow_hash = aptos_hash::keccak256(
            bcs::to_bytes(&vector[bcs::to_bytes(&order_hash), bcs::to_bytes(&SALT)])
        );
        let escrow_address = account::create_resource_address(&signer::address_of(&depositor), escrow_hash);

        // Fast forward to withdrawal time
        timestamp::update_global_time_for_test_secs(1000 + WITHDRAW_PERIOD + 50);

        let receiver_initial_deposit = primary_fungible_store::balance(@0x789, deposit_metadata);
        let receiver_initial_incentive = primary_fungible_store::balance(@0x789, incentive_metadata);

        // Withdraw with correct secret
        order_factory::withdraw(
            &receiver,
            escrow_address,
            SECRET,
            incentive_metadata,
            deposit_metadata
        );

        // Verify receiver got the deposit
        let receiver_final_deposit = primary_fungible_store::balance(@0x789, deposit_metadata);
        assert!(receiver_final_deposit == receiver_initial_deposit + DEPOSIT_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x1)]
    fun test_withdraw_with_invalid_secret() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"test_order_hash";

        // Create destination escrow
        order_factory::create_escrow_dst(
            &depositor,
            order_hash,
            signer::address_of(&receiver),
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate escrow address
        let escrow_hash = aptos_hash::keccak256(
            bcs::to_bytes(&vector[bcs::to_bytes(&order_hash), bcs::to_bytes(&SALT)])
        );
        let escrow_address = account::create_resource_address(&signer::address_of(&depositor), escrow_hash);

        // Fast forward to withdrawal time
        timestamp::update_global_time_for_test_secs(1000 + WITHDRAW_PERIOD + 50);

        // Try to withdraw with wrong secret - should fail
        order_factory::withdraw(
            &receiver,
            escrow_address,
            b"wrong_secret",
            incentive_metadata,
            deposit_metadata
        );
    }

    #[test]
    fun test_cancel_escrow() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"test_order_hash";

        // Create destination escrow
        order_factory::create_escrow_dst(
            &depositor,
            order_hash,
            signer::address_of(&receiver),
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate escrow address
        let escrow_hash = aptos_hash::keccak256(
            bcs::to_bytes(&vector[bcs::to_bytes(&order_hash), bcs::to_bytes(&SALT)])
        );
        let escrow_address = account::create_resource_address(&signer::address_of(&depositor), escrow_hash);

        // Fast forward to cancel time
        timestamp::update_global_time_for_test_secs(1000 + CANCEL_PERIOD + 50);

        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let depositor_initial_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);

        // Cancel by depositor
        order_factory::cancel(
            &depositor,
            escrow_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back the deposit and incentive fee
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let depositor_final_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);

        assert!(depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT, 1);
        assert!(depositor_final_incentive == depositor_initial_incentive + INCENTIVE_FEE, 2);
    }

    #[test]
    fun test_recover_order() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // Create order only (no escrow)
        order_factory::create_order(
            &relay,
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            true,
            vector::empty<address>(),
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate order address
        let order_hash = get_order_address(
            &depositor,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );
        let order_address = account::create_resource_address(&signer::address_of(&depositor), order_hash);

        // Fast forward past recovery period
        timestamp::update_global_time_for_test_secs(1000 + RECOVER_PERIOD + 50);

        let anyone = account::create_account_for_test(@0x999);
        mint_test_tokens(&creator, @0x999, 0);

        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        let anyone_initial_incentive = primary_fungible_store::balance(@0x999, incentive_metadata);

        // Anyone can recover after the period
        order_factory::recover(
            &anyone,
            order_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back their deposit
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT, 1);

        // Verify recoverer got the recovery incentive fee
        let anyone_final_incentive = primary_fungible_store::balance(@0x999, incentive_metadata);
        assert!(anyone_final_incentive == anyone_initial_incentive + RECOVER_INCENTIVE_FEE, 2);
    }

    #[test]
    #[expected_failure(abort_code = 4)] // EINVALID_TIMELOCK_STATE
    fun test_recover_before_period() acquires TestTokenRefs {
        let (creator, relay, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // Create order only
        order_factory::create_order(
            &relay,
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            true,
            vector::empty<address>(),
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Calculate order address
        let order_hash = get_order_address(
            &depositor,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );
        let order_address = account::create_resource_address(&signer::address_of(&depositor), order_hash);

        let anyone = account::create_account_for_test(@0x999);

        // Should fail because recovery period hasn't passed
        order_factory::recover(
            &anyone,
            order_address,
            incentive_metadata,
            deposit_metadata
        );
    }
}
