script {
    use escrow_factory::order_factory;
    use aptos_framework::object::{
        Self,
        Object,
        ConstructorRef,
        create_named_object,
        object_from_constructor_ref
    };
    use aptos_framework::primary_fungible_store::{Self, deposit};
    use aptos_framework::fungible_asset::{Self, Metadata, generate_mint_ref, mint};
    use std::string;
    use std::debug;
    use std::option;
    use aptos_std::signer;
    use aptos_std::base16;

    /*
    Script used to deploy mock tokens. The user and resolver address should be provided.
    The script will give balances of both mock tokens to these addresses.

    To run: 
        - `aptos move compile`
        - `aptos move run-script --compiled-script-path ./build/order-factory/bytecode_script/main`
    */
    entry fun main(account: &signer) {
        // Addresses for the relay and user, replace with addresses you want to use
        let resolver_addr =
            @0x50fb544445622bee716f1a50c93ea72fe18525ac7f18daa617ff6d74a28f9f93;
        let user_addr =
            @0x3926348fbe4db32987c5ff2306d67efe3450bd9c5fc58745f7852f9ef4dc13f1;

        // Create Incentive Token
        let incentive_constructor_ref = &create_named_object(account, b"IncentiveCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            incentive_constructor_ref,
            option::none(),
            string::utf8(b"Incentive Coin"),
            string::utf8(b"INC1"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let incentive_metadata: Object<Metadata> =
            object_from_constructor_ref<Metadata>(incentive_constructor_ref);

        // Create Deposit Token
        let deposit_constructor_ref = &create_named_object(account, b"DepositCoin");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            deposit_constructor_ref,
            option::none(),
            string::utf8(b"Deposit Coin"),
            string::utf8(b"DEP1"),
            8,
            string::utf8(b""),
            string::utf8(b"")
        );
        let deposit_metadata: Object<Metadata> =
            object_from_constructor_ref<Metadata>(deposit_constructor_ref);

        let my_addr = signer::address_of(account);

        // Mint test incentive tokens
        let incentive_mint_ref = generate_mint_ref(incentive_constructor_ref);
        let minted_incentive = mint(&incentive_mint_ref, 10000000);
        deposit(my_addr, minted_incentive);
        let minted_incentive = mint(&incentive_mint_ref, 10000000);
        deposit(user_addr, minted_incentive);
        let minted_incentive = mint(&incentive_mint_ref, 10000000);
        deposit(resolver_addr, minted_incentive);

        // int test deposit tokens
        let deposit_mint_ref = generate_mint_ref(deposit_constructor_ref);
        let minted_deposit = mint(&deposit_mint_ref, 10000000);
        deposit(my_addr, minted_deposit);
        let minted_incentive = mint(&deposit_mint_ref, 10000000);
        deposit(user_addr, minted_incentive);
        let minted_incentive = mint(&deposit_mint_ref, 10000000);
        deposit(resolver_addr, minted_incentive);

        // Print the addresses of both token objects
        debug::print(&string::utf8(b"Incentive Token Object Address:"));
        debug::print(&object::object_address(&incentive_metadata));
        debug::print(&string::utf8(b"Deposit Token Object Address:"));
        debug::print(&object::object_address(&deposit_metadata));

        // Print the factory contract address (the account address)
        debug::print(&string::utf8(b"Factory contract (module) address:"));
        debug::print(&my_addr);
    }
}