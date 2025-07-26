module addr::factory {
    use std::error;
    use std::signer;
    use std::string;
    use aptos_std::bcs;
    use aptos_framework::event;
    use aptos_std::table::{Table, self};

    struct EscrowStore has key, store {
        inner: Table<bytes32, Escrow>,
    }

    struct Escrow<T> has key, store {
        // Used to incentivize resolvers to run actions.
        incentiveFee: Token,
        // Token being escrowed.
        token : Token,
        // Merkle root of the hashlog.
        secret: vector<u8>,
        // Address of the depositor.
        depositor: address,
        // Address of the receiver. (this may be a receiver on another chain)
        receiver: address,

        // Timelock parameters.
        withdrawTimestamp: u64,
        publicWithDrawTimestamp: u64,
        cancelTimestamp: u64,
        publicCancelTimestamp: u64,
        recoverTimestamp: u64,
    }

    public fun createEscrow<T>(address: signer, 
            incentiveFee: T,
            token: T, 
            orderHash: vector<u8>,
            salt: vector<u8>,
            hashlog: vector<u8>,
            withdrawTimestamp: u64,
            publicWithDrawTimestamp: u64,
            cancelTimestamp: u64,
            publicCancelTimestamp: u64,
            recoverTimestamp: u64
        ) {

        let escrowAddress = bcs::from_bytes<address>(&orderHash);
        
        let escrow = Escrow {
            incentiveFee,
            token,
            secret: hashlog,
            depositor: signer::address_of(&signer),
            receiver: signer::address_of(&signer),
            withdrawTimestamp,
            publicWithDrawTimestamp,
            cancelTimestamp,
            publicCancelTimestamp,
            recoverTimestamp,
        };

        // Check if signer has a store
        if (!exists<Store>(signer)) {
            move_to(signer, MyResource { inner: table::new<address, Escrow>() });
        };

        let store = borrow_global_mut<Store>(signer);
        let inner = &mut store.inner;
        
        // Hash the salt and the orderHash to create a unique key
        let key = bcs::to_bytes(&orderHash) + bcs::to_bytes(&salt);
        let key_hash = table::hash(key);

        // Insert the escrow into the store
        table::add(inner, key_hash, escrow);
    }

    // TODO withdraw
    // - Should use a merkle tree to recover the root 

    // TODO cancel

    // TODO recover
}