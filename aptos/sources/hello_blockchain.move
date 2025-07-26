module escrow_addr::escrow_src {
    use std::error;
    use std::signer;
    use std::string;
    use aptos_framework::event;
    #[test_only]
    use std::debug;

    // //:!:>resource
    // struct MessageHolder has key {
    //     message: string::String,
    // }

//   struct Immutables {
//         bytes32 orderHash;
//         bytes32 hashlock;  // Hash of the secret.
//         Address maker;
//         Address taker;
//         Address token;
//         uint256 amount;
//         uint256 safetyDeposit;
//         Timelocks timelocks;
//     }


//    SrcWithdrawal,
//         SrcPublicWithdrawal,
//         SrcCancellation,
//         SrcPublicCancellation,
//         DstWithdrawal,
//         DstPublicWithdrawal,
//         DstCancellation

    struct Timelocks {
        deployTimeStamp: u32, // Timestamp of the order deployment.
        dstWithdrawTimePeriod: u32, // Time period for private withdrawal.
        dstPublicWithdrawTimePeriod: u32, // Time period for public withdrawal.
        srcWithdrawTimePeriod: u32, // Time period for private withdrawal.
        srcPublicWithdrawTimePeriod: u32, // Time period for public withdrawal.
        dstCancellationTimePeriod: u32, // Time period for private cancellation.
        dstPublicCancellationTimePeriod: u32, // Time period for public cancellation.
        srcCancellationTimePeriod: u32, // Time period for private cancellation.
        srcPublicCancellationTimePeriod: u32, // Time period for public cancellation.
    }

    struct Immutables {
        order_hash: vector<u8>,
        hashlock: vector<u8>, // Hash of the secret.
        maker: address,
        taker: address,
        token: address,
        amount: u64,
        safety_deposit: u64,
        timelocks: Timelocks,
    }

    struct EscrowSrcState has key {
        rescueDelay: u32, // Delay before the rescue can be executed.
        // TODO access token
    }

    // Taker runs transaction on behalf of Maker (signer)
    public entry fun create_src(account: Signer) {
        // Create new EscrowSrc contract
        // - Maker Address
        // - Taker Address
        // - Secret 
        // - Tokens
        // - Timelock
        // Move escrowSrc to Taker Address escrowSrc Map
    }

    // TODO validate src (used be maker to check dst correct)

    // Taker (signer) runs transaction 
    public entry fun create_dst(account: Signer) {
        // Create new EscrowDST
        // - Maker Address
        // - Taker Address
        // - Secret
        // - Tokens
        // - Timelock
        // Move escrowDst to Taker escrowDst Map
    }

    // TODO validate DST (used by maker to check dst correct)

    // Anyone (signer)
    public entry fun withdraw_src(account: Signer) {
        // Find the escrowSrc in taker dict
        // Reveal secret
        // Check timelock
        // Send funds to Taker
    }

    // Anyone (signer)
    public entry fun withdraw_dst(account: Signer) {
        // Find the escrowDst in taker dict
        // Reveal secret
        // Check timelock
        // Send fund to Maker
    }

    // TODO timelock contracts etc.



    // #[event]
    // struct MessageChange has drop, store {
    //     account: address,
    //     from_message: string::String,
    //     to_message: string::String,
    // }

    /// There is no message present
    const ENO_MESSAGE: u64 = 0;

    #[view]
    public fun get_message(addr: address): string::String acquires MessageHolder {
        assert!(exists<MessageHolder>(addr), error::not_found(ENO_MESSAGE));
        borrow_global<MessageHolder>(addr).message
    }

    public entry fun set_message(account: signer, message: string::String)
    acquires MessageHolder {
        let account_addr = signer::address_of(&account);
        if (!exists<MessageHolder>(account_addr)) {
            move_to(&account, MessageHolder {
                message,
            })
        } else {
            let old_message_holder = borrow_global_mut<MessageHolder>(account_addr);
            let from_message = old_message_holder.message;
            event::emit(MessageChange {
                account: account_addr,
                from_message,
                to_message: copy message,
            });
            old_message_holder.message = message;
        }
    }

    #[test(account = @0x1)]
    public entry fun sender_can_set_message(account: signer) acquires MessageHolder {
        let msg: string::String = string::utf8(b"Running test for sender_can_set_message...");
        debug::print(&msg);

        let addr = signer::address_of(&account);
        aptos_framework::account::create_account_for_test(addr);
        set_message(account, string::utf8(b"Hello, Blockchain"));

        assert!(
            get_message(addr) == string::utf8(b"Hello, Blockchain"),
            ENO_MESSAGE
        );
    }
}