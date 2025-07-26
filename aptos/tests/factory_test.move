module {{addr}}::token_router_test {
    use aptos_std::test;
    use std::signer;
    use {{addr}}::token_router;
    use {{addr}}::mock_token::{self, Token};

    #[test]
    public fun move_and_claim() {
        // Create two testing signers.
        let (owner, receiver) = test::create_signers(2);

        // Owner publishes a Bin<mock_token::Token>.
        token_router::init<Token>(&owner);

        // Mint a mock token and send it to the receiver’s slot.
        let t = mock_token::new(42);
        token_router::send<Token>(&owner, t, signer::address_of(&receiver));

        // Receiver claims it.
        let claimed = token_router::claim<Token>(&receiver, signer::address_of(&owner));

        // Assert the round-trip succeeded.
        assert!(claimed.id == 42, 0);
    }
}