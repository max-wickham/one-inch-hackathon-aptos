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
    const SECRET: vector<u8> = b"test_secret_123";

    // Global storage for mint references
    struct TestTokenRefs has key {
        incentive_mint_ref: MintRef,
        incentive_burn_ref: BurnRef,
        incentive_metadata: Object<Metadata>,
        deposit_mint_ref: MintRef,
        deposit_burn_ref: BurnRef,
        deposit_metadata: Object<Metadata>,
    }


    // #[test_only]
    // fun create_test_token(creator: &signer, name: vector<u8>): Object<Metadata> {
    //     let constructor_ref = &object::create_named_object(creator, name);
    //     primary_fungible_store::create_primary_store_enabled_fungible_asset(
    //         constructor_ref,
    //         option::none(),
    //         string::utf8(b"Test Coin"),
    //         string::utf8(b"TEST"),
    //         8,
    //         string::utf8(b""),
    //         string::utf8(b""),
    //     );

    //     // Store the mint and burn refs
    //     let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
    //     let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
    //     let token_refs = TestTokenRefs {
    //         mint_ref,
    //         burn_ref,
    //     };
    //     move_to(creator, token_refs);

    //     object::object_from_constructor_ref(constructor_ref)
    // }

    #[test_only]
    fun create_test_tokens(creator: &signer): (Object<Metadata>, Object<Metadata>) {
        // Create incentive token
        let incentive_constructor_ref = &object::create_named_object(creator, b"IncentiveCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            incentive_constructor_ref,
            option::none(),
            string::utf8(b"Incentive Coin"),
            string::utf8(b"INC"),
            8,
            string::utf8(b""),
            string::utf8(b""),
        );
        
        let incentive_metadata = object::object_from_constructor_ref(incentive_constructor_ref);
        let incentive_mint_ref = fungible_asset::generate_mint_ref(incentive_constructor_ref);
        let incentive_burn_ref = fungible_asset::generate_burn_ref(incentive_constructor_ref);

        // Create deposit token
        let deposit_constructor_ref = &object::create_named_object(creator, b"DepositCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            deposit_constructor_ref,
            option::none(),
            string::utf8(b"Deposit Coin"),
            string::utf8(b"DEP"),
            8,
            string::utf8(b""),
            string::utf8(b""),
        );

        let deposit_metadata = object::object_from_constructor_ref(deposit_constructor_ref);
        let deposit_mint_ref = fungible_asset::generate_mint_ref(deposit_constructor_ref);
        let deposit_burn_ref = fungible_asset::generate_burn_ref(deposit_constructor_ref);

        // Store both token references in a single resource
        let token_refs = TestTokenRefs {
            incentive_mint_ref,
            incentive_burn_ref,
            incentive_metadata,
            deposit_mint_ref,
            deposit_burn_ref,
            deposit_metadata,
        };
        move_to(creator, token_refs);

        (incentive_metadata, deposit_metadata)
    }



    #[test_only]
    fun mint_test_tokens(
        creator: &signer,
        to: address,
        amount: u64
    ) acquires TestTokenRefs {
        let token_refs = borrow_global<TestTokenRefs>(signer::address_of(creator));
        let fa = fungible_asset::mint(&token_refs.incentive_mint_ref, amount);
        primary_fungible_store::deposit(to, fa);
        let fa = fungible_asset::mint(&token_refs.deposit_mint_ref, amount);
        primary_fungible_store::deposit(to, fa);
    }

    #[test_only]
    fun setup_test_environment(): (signer, signer, signer, Object<Metadata>, Object<Metadata>)  acquires TestTokenRefs {
        timestamp::set_time_has_started_for_testing(&account::create_signer_for_test(@0x1));
        timestamp::update_global_time_for_test_secs(1000);

        let creator = account::create_account_for_test(@0x123);
        let depositor = account::create_account_for_test(@0x456);
        let receiver = account::create_account_for_test(@0x789);

        // Create two different test tokens with unique names
        let (incentive_metadata, deposit_metadata) = create_test_tokens(&creator);

        // Mint tokens to depositor
        mint_test_tokens(&creator, @0x456, 10000);

        (creator, depositor, receiver, incentive_metadata, deposit_metadata)
    }

    #[test]
    fun test_create_escrow_success() acquires TestTokenRefs {
        let (creator, depositor, _receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_123";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,  // withdrawTimestamp
            current_time + 200,  // publicWithDrawTimestamp
            current_time + 300,  // cancelTimestamp
            current_time + 400,  // publicCancelTimestamp
            current_time + 500   // recoverTimestamp
        );

        // Verify depositor's balance decreased
        let depositor_incentive_balance = primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_deposit_balance = primary_fungible_store::balance(@0x456, deposit_metadata);
        assert!(depositor_incentive_balance == 10000 - INCENTIVE_FEE, 1);
        assert!(depositor_deposit_balance == 10000 - DEPOSIT_AMOUNT, 2);

        // Verify vault has the assets
        let vault_incentive_balance = primary_fungible_store::balance(vault_address, incentive_metadata);
        let vault_deposit_balance = primary_fungible_store::balance(vault_address, deposit_metadata);
        assert!(vault_incentive_balance == INCENTIVE_FEE, 3);
        assert!(vault_deposit_balance == DEPOSIT_AMOUNT, 4);
    }

    #[test]
    fun test_withdraw_with_valid_secret_by_receiver()  acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_124";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,  // withdrawTimestamp
            current_time + 200,  // publicWithDrawTimestamp
            current_time + 300,  // cancelTimestamp
            current_time + 400,  // publicCancelTimestamp
            current_time + 500   // recoverTimestamp
        );

        // Fast forward to withdrawal time
        timestamp::update_global_time_for_test_secs(current_time + 150);

        // Withdraw by receiver with correct secret
        factory::withdraw(
            &receiver,
            vault_address,
            SECRET,
            incentive_metadata,
            deposit_metadata
        );

        // Verify receiver got the incentive fee
        let receiver_incentive_balance = primary_fungible_store::balance(@0x789, incentive_metadata);
        assert!(receiver_incentive_balance == INCENTIVE_FEE, 0);

        // Verify receiver got the deposit
        let receiver_deposit_balance = primary_fungible_store::balance(@0x789, deposit_metadata);
        assert!(receiver_deposit_balance == DEPOSIT_AMOUNT, 1);
    }

    #[test]
    fun test_withdraw_during_public_period()  acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_125";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,  // withdrawTimestamp
            current_time + 200,  // publicWithDrawTimestamp
            current_time + 300,  // cancelTimestamp
            current_time + 400,  // publicCancelTimestamp
            current_time + 500   // recoverTimestamp
        );

        // Fast forward to public withdrawal period
        timestamp::update_global_time_for_test_secs(current_time + 250);

        // Anyone can withdraw during public period with correct secret
        let anyone = account::create_account_for_test(@0x999);
        factory::withdraw(
            &anyone,
            vault_address,
            SECRET,
            incentive_metadata,
            deposit_metadata
        );

        // Verify anyone got the incentive fee
        let anyone_incentive_balance = primary_fungible_store::balance(@0x999, incentive_metadata);
        assert!(anyone_incentive_balance == INCENTIVE_FEE, 0);

        // Verify receiver still gets the deposit
        let receiver_deposit_balance = primary_fungible_store::balance(@0x789, deposit_metadata);
        assert!(receiver_deposit_balance == DEPOSIT_AMOUNT, 1);
    }

    #[test]
    #[expected_failure(abort_code = 0x1)]
    fun test_withdraw_with_invalid_secret()  acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_126";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,
            current_time + 200,
            current_time + 300,
            current_time + 400,
            current_time + 500
        );

        timestamp::update_global_time_for_test_secs(current_time + 150);

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
    fun test_cancel_by_depositor() acquires TestTokenRefs  {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_128";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,
            current_time + 200,
            current_time + 300,  // cancelTimestamp
            current_time + 400,
            current_time + 500
        );

        // Fast forward to cancel time
        timestamp::update_global_time_for_test_secs(current_time + 350);

        let depositor_initial_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);

        // Cancel by depositor
        factory::cancel(
            &depositor,
            vault_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back both incentive fee and deposit
        let depositor_final_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);

        assert!(depositor_final_incentive == depositor_initial_incentive + INCENTIVE_FEE, 0);
        assert!(depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT, 1);
    }

    #[test]
    fun test_recover_by_depositor()  acquires TestTokenRefs {
        let (creator, depositor, receiver, incentive_metadata, deposit_metadata) = setup_test_environment();

        let hashlock = aptos_hash::keccak256(SECRET);
        let order_hash = b"unique_order_130";

        let current_time = timestamp::now_seconds();
        let vault_address = factory::createEscrow(
            &depositor,
            incentive_metadata,
            deposit_metadata,
            INCENTIVE_FEE,
            DEPOSIT_AMOUNT,
            order_hash,
            hashlock,
            @0x789,
            current_time + 100,
            current_time + 200,
            current_time + 300,
            current_time + 400,
            current_time + 500   // recoverTimestamp
        );

        // Fast forward to recover time
        timestamp::update_global_time_for_test_secs(current_time + 600);

        let depositor_initial_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_initial_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);

        // Recover by depositor
        factory::recover(
            &depositor,
            vault_address,
            incentive_metadata,
            deposit_metadata
        );

        // Verify depositor got back both incentive fee and deposit
        let depositor_final_incentive = primary_fungible_store::balance(@0x456, incentive_metadata);
        let depositor_final_deposit = primary_fungible_store::balance(@0x456, deposit_metadata);

        assert!(depositor_final_incentive == depositor_initial_incentive + INCENTIVE_FEE, 0);
        assert!(depositor_final_deposit == depositor_initial_deposit + DEPOSIT_AMOUNT, 1);
    }
}
