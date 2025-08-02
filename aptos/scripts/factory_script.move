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

    entry fun main(account: &signer) {
        // Addresses for the relay and user, replace with addresses you want to use
        let relay_addr =
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
        deposit(relay_addr, minted_incentive);

        // int test deposit tokens
        let deposit_mint_ref = generate_mint_ref(deposit_constructor_ref);
        let minted_deposit = mint(&deposit_mint_ref, 10000000);
        deposit(my_addr, minted_deposit);
        let minted_incentive = mint(&deposit_mint_ref, 10000000);
        deposit(user_addr, minted_incentive);
        let minted_incentive = mint(&deposit_mint_ref, 10000000);
        deposit(relay_addr, minted_incentive);

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

script {
    use escrow_factory::order_factory;
    use aptos_framework::object::{
        Self,
        Object,
        ConstructorRef,
        create_named_object,
        object_from_constructor_ref,
        address_to_object
    };
    use aptos_framework::primary_fungible_store::{Self, deposit};
    use aptos_framework::fungible_asset::{Self, Metadata, generate_mint_ref, mint};
    use std::string;
    use std::debug;
    use std::option;
    use aptos_std::signer;
    use std::vector;
    use aptos_std::base16;

    entry fun create_order(account: &signer) {
        let incentive_token_address =
            @0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d;
        let deposit_token_address =
            @0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e;
        let factory_address =
            @0xe6727f9d55fa8f220cc4735507b709eaa80b569de07bce38d03c305027554c52;

        let deposit_token_asset_metadata =
            address_to_object<Metadata>(deposit_token_address);
        let incentive_fee_asset_metadata =
            address_to_object<Metadata>(incentive_token_address);

        // Order parameters (edit as needed)
        let recover_incentive_fee = 10;
        let recover_period = 86400;
        let deposit_amount = 100;
        let min_incentive_fee = 10;
        let salt = b"my_salt_3";
        let hashlock = b"my_hashlock";
        let hashlock =
            x"9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658";
        let allow_multi_fill = true;
        let whitelisted_addresses = vector::empty<address>();
        let withdraw_period = 10;
        let public_withdraw_period = 7200;
        let cancel_period = 10800;
        let public_cancel_period = 14400;

        order_factory::create_order(
            account,
            account,
            deposit_token_asset_metadata,
            incentive_fee_asset_metadata,
            recover_incentive_fee,
            recover_period,
            deposit_amount,
            min_incentive_fee,
            salt,
            hashlock,
            allow_multi_fill,
            whitelisted_addresses,
            withdraw_period,
            public_withdraw_period,
            cancel_period,
            public_cancel_period
        );
    }
}

script {
    use escrow_factory::order_factory;
    use aptos_framework::object::{
        Self,
        Object,
        ConstructorRef,
        create_named_object,
        object_from_constructor_ref,
        address_to_object
    };
    use aptos_framework::primary_fungible_store::{Self, deposit};
    use aptos_framework::fungible_asset::{Self, Metadata, generate_mint_ref, mint};
    use std::string;
    use std::debug;
    use std::option;
    use aptos_std::signer;
    use std::vector;
    use aptos_std::base16;

    entry fun create_src(account: &signer) {
        let order_address =
            @0x879c886f03d197e18001f23cbd51b611f0e5cf35564a83536e226615ba089ccc; // <-- FILL IN with the order's resource account address
        let incentive_token_address =
            @0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d;
        let deposit_token_address =
            @0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e;
        let factory_address =
            @0xe6727f9d55fa8f220cc4735507b709eaa80b569de07bce38d03c305027554c52;

        let deposit_token_asset_metadata =
            address_to_object<Metadata>(deposit_token_address);
        let incentive_fee_asset_metadata =
            address_to_object<Metadata>(incentive_token_address);

        // Escrow parameters
        let make_amount = 100; // Amount to escrow (must be ≤ order.deposit_amount)
        let incentive_fee = 12; // Must be > order.min_incentive_fee
        let receiver =
            @0xe6727f9d55fa8f220cc4735507b709eaa80b569de07bce38d03c305027554c52; // <-- FILL IN with the receiver's address
        let salt = b"my_escrow_salt_3"; // Unique salt per escrow

        order_factory::create_escrow_src<Metadata, Metadata>(
            account,
            order_address,
            incentive_fee_asset_metadata,
            deposit_token_asset_metadata,
            make_amount,
            incentive_fee,
            receiver,
            salt
        );
    }
}

script {
    use escrow_factory::order_factory;
    use aptos_framework::object::{
        Self,
        Object,
        ConstructorRef,
        create_named_object,
        object_from_constructor_ref,
        address_to_object
    };
    use aptos_framework::primary_fungible_store::{Self, deposit};
    use aptos_framework::fungible_asset::{Self, Metadata, generate_mint_ref, mint};
    use std::string;
    use std::debug;
    use std::option;
    use aptos_std::signer;
    use std::vector;
    use aptos_std::base16;

    entry fun withdraw(account: &signer) {
        let escrow_address =
            @0xca57a416b42643ce2d739be39cdc55d7104891d447e0ae63cb1ebf04d33c917e;
        let factory_address =
            @0xe6727f9d55fa8f220cc4735507b709eaa80b569de07bce38d03c305027554c52;
        let incentive_token_address =
            @0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d;
        let deposit_token_address =
            @0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e;

        let deposit_token_asset_metadata =
            address_to_object<Metadata>(deposit_token_address);
        let incentive_fee_asset_metadata =
            address_to_object<Metadata>(incentive_token_address);

        // The secret that unlocks the hashlock (must match what was used to create the escrow)
        let secret = b"test"; // or use x"..." for hex

        let deposit_token_asset_metadata =
            address_to_object<Metadata>(deposit_token_address);
        let incentive_fee_asset_metadata =
            address_to_object<Metadata>(incentive_token_address);

        order_factory::withdraw<Metadata, Metadata>(
            account,
            escrow_address,
            secret,
            incentive_fee_asset_metadata,
            deposit_token_asset_metadata
        );
    }
}
