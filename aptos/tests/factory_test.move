#[test_only]
module escrow_factory::factory_tests {
    use std::string;
    use std::vector;
    use std::option;
    use aptos_std::timestamp;
    use aptos_std::signer;

    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, MintRef, BurnRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use escrow_factory::factory;
    use aptos_std::aptos_hash;

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
    fun setup_test_environment(): (signer, signer, signer, Object<Metadata>, Object<Metadata>) acquires TestTokenRefs {
        timestamp::set_time_has_started_for_testing(
            &account::create_signer_for_test(@0x1)
        );
        timestamp::update_global_time_for_test_secs(1000);

        let creator = account::create_account_for_test(@0x123);
        let depositor = account::create_account_for_test(@0x456);
        let receiver = account::create_account_for_test(@0x789);

        // Create two different test tokens with unique names
        let (incentive_metadata, deposit_metadata) = create_test_tokens(&creator);

        // Mint tokens to both depositor and receiver
        // Depositor needs deposit + recovery incentive fee
        // Receiver needs their own incentive fee
        mint_test_tokens(&creator, @0x456, 10000);
        mint_test_tokens(&creator, @0x789, 10000);

        (creator, depositor, receiver, incentive_metadata, deposit_metadata)
    }

    #[test_only]
    fun create_order_and_escrow(
        depositor: &signer,
        receiver: &signer,
        incentive_metadata: Object<Metadata>,
        deposit_metadata: Object<Metadata>,
        deposit_amount: u64,
        incentive_fee: u64,
        salt: vector<u8>
    ): address {
        let hashlock = aptos_hash::keccak256(SECRET);

        // Step 1: Create order (depositor provides deposit + recovery incentive fee)
        let order_address = factory::createOrder(
            depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            deposit_amount,
            MIN_INCENTIVE_FEE,
            salt,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Step 2: Create escrow (receiver provides their own incentive fee)
        let vault_address = factory::createEscrow(
            receiver,
            order_address,
            incentive_metadata,
            deposit_metadata,
            deposit_amount, // makeAmount
            incentive_fee,
            signer::address_of(receiver)
        );

        vault_address
    }

    #[test]
    fun test_create_escrow_success() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let vault_address = create_order_and_escrow(
            &depositor,
            &receiver,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            SALT
        );

        // Verify depositor's balances decreased (deposit + recovery incentive fee)
        let depositor_incentive_balance =
            primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_deposit_balance =
            primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(
            depositor_incentive_balance == 10000 - RECOVER_INCENTIVE_FEE,
            1
        );
        assert!(
            depositor_deposit_balance == 10000 - DEPOSIT_AMOUNT,
            2
        );

        // Verify receiver's incentive balance decreased (their own incentive fee)
        let receiver_incentive_balance =
            primary_fungible_store::balance(@0x789, incentive_metadata);
        assert!(
            receiver_incentive_balance == 10000 - INCENTIVE_FEE,
            3
        );

        // Verify vault has both incentive fees + deposit
        let vault_incentive_balance =
            primary_fungible_store::balance(vault_address, incentive_metadata);
        let vault_deposit_balance =
            primary_fungible_store::balance(vault_address, deposit_metadata);
        assert!(vault_incentive_balance == INCENTIVE_FEE, 4);
        assert!(vault_deposit_balance == DEPOSIT_AMOUNT, 5);
    }

    #[test]
    fun test_withdraw_with_valid_secret_by_receiver() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let vault_address = create_order_and_escrow(
            &depositor,
            &receiver,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            b"unique_salt_124"
        );

        // Fast forward to withdrawal time
        timestamp::update_global_time_for_test_secs(1000 + WITHDRAW_PERIOD + 50);

        // Withdraw by receiver with correct secret
        factory::withdraw(
            &receiver,
            vault_address,
            SECRET,
            incentive_metadata,
            deposit_metadata
        );

        // Verify receiver got the incentive fee (their own back + earned it)
        let receiver_incentive_balance =
            primary_fungible_store::balance(@0x789, incentive_metadata);
        assert!(receiver_incentive_balance == 10000 - INCENTIVE_FEE + INCENTIVE_FEE, 0);

        // Verify receiver got the deposit
        let receiver_deposit_balance =
            primary_fungible_store::balance(@0x789, deposit_metadata);
        assert!(receiver_deposit_balance == 10000 + DEPOSIT_AMOUNT, 1);
    }

    #[test]
    fun test_withdraw_during_public_period() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let vault_address = create_order_and_escrow(
            &depositor,
            &receiver,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            b"unique_salt_125"
        );

        // Fast forward to public withdrawal period
        timestamp::update_global_time_for_test_secs(1000 + PUBLIC_WITHDRAW_PERIOD + 50);

        // Anyone can withdraw during public period with correct secret
        let anyone = account::create_account_for_test(@0x999);
        mint_test_tokens(&creator, @0x999, 0); // Just to create the primary store

        factory::withdraw(
            &anyone,
            vault_address,
            SECRET,
            incentive_metadata,
            deposit_metadata
        );

        // Verify anyone got the incentive fee
        let anyone_incentive_balance =
            primary_fungible_store::balance(@0x999, incentive_metadata);
        assert!(anyone_incentive_balance == INCENTIVE_FEE, 0);

        // Verify receiver still gets the deposit
        let receiver_deposit_balance =
            primary_fungible_store::balance(@0x789, deposit_metadata);
        assert!(receiver_deposit_balance == 10000 + DEPOSIT_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x1)]
    fun test_withdraw_with_invalid_secret() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let vault_address = create_order_and_escrow(
            &depositor,
            &receiver,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            b"unique_salt_126"
        );

        timestamp::update_global_time_for_test_secs(1000 + WITHDRAW_PERIOD + 50);

        // Try to withdraw with wrong secret
        factory::withdraw(
            &receiver,
            vault_address,
            b"wrong_secret",
            incentive_metadata,
            deposit_metadata
        );
    }

    #[test]
    fun test_cancel_by_depositor() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let vault_address = create_order_and_escrow(
            &depositor,
            &receiver,
            incentive_metadata,
            deposit_metadata,
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            b"unique_salt_128"
        );

        // Fast forward to cancel time
        timestamp::update_global_time_for_test_secs(1000 + CANCEL_PERIOD + 50);

        let depositor_initial_incentive =
            primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_initial_deposit =
            primary_fungible_store::balance(@0x456, deposit_metadata);

        // Cancel by depositor
        factory::cancel(
            &depositor,
            vault_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back the deposit
        let depositor_final_deposit =
            primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(
            depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT,
            1
        );

        // Verify depositor got the receiver's incentive fee
        let depositor_final_incentive =
            primary_fungible_store::balance(@0x456, incentive_metadata);
        assert!(
            depositor_final_incentive == depositor_initial_incentive + INCENTIVE_FEE,
            0
        );
    }

    #[test]
    fun test_recover_by_anyone_after_period() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // Create order only (no escrow)
        let order_address = factory::createOrder(
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Fast forward past recovery period
        timestamp::update_global_time_for_test_secs(1000 + RECOVER_PERIOD + 50);

        let anyone = account::create_account_for_test(@0x999);
        mint_test_tokens(&creator, @0x999, 0); // Just to create the primary store

        let depositor_initial_deposit =
            primary_fungible_store::balance(@0x456, deposit_metadata);
        let anyone_initial_incentive =
            primary_fungible_store::balance(@0x999, incentive_metadata);

        // Anyone can recover after the period
        factory::recover(
            &anyone,
            order_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back their deposit
        let depositor_final_deposit =
            primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(
            depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT,
            0
        );

        // Verify recoverer got the recovery incentive fee
        let anyone_final_incentive =
            primary_fungible_store::balance(@0x999, incentive_metadata);
        assert!(
            anyone_final_incentive == anyone_initial_incentive + RECOVER_INCENTIVE_FEE,
            1
        );
    }

    #[test]
    #[expected_failure(abort_code = 4)] // EINVALID_TIMELOCK_STATE
    fun test_recover_before_period() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // Create order only
        let order_address = factory::createOrder(
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Don't fast forward - try to recover immediately
        let anyone = account::create_account_for_test(@0x999);

        // Should fail because recovery period hasn't passed
        factory::recover(
            &anyone,
            order_address,
            incentive_metadata,
            deposit_metadata
        );
    }

    #[test]
    #[expected_failure(abort_code = 5)] // EINVALID_ASSET_TYPE
    fun test_create_escrow_with_wrong_asset_type() acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) =
            setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);

        // Create order with correct asset types
        let order_address = factory::createOrder(
            &depositor,
            deposit_metadata,
            incentive_metadata,
            RECOVER_INCENTIVE_FEE,
            RECOVER_PERIOD,
            DEPOSIT_AMOUNT,
            MIN_INCENTIVE_FEE,
            SALT,
            hashlock,
            WITHDRAW_PERIOD,
            PUBLIC_WITHDRAW_PERIOD,
            CANCEL_PERIOD,
            PUBLIC_CANCEL_PERIOD
        );

        // Try to create escrow with wrong asset types (swapped)
        factory::createEscrow(
            &receiver,
            order_address,
            deposit_metadata, // Wrong! Should be incentive_metadata
            incentive_metadata, // Wrong! Should be deposit_metadata
            DEPOSIT_AMOUNT,
            INCENTIVE_FEE,
            signer::address_of(&receiver)
        );
    }
}
