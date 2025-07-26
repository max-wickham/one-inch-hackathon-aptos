module {{addr}}::mock_token {
    /// A fake, non-fungible token consisting of an `id`.
    struct Token has key, store {
        id: u64,
    }

    public fun new(id: u64): Token {
        Token { id }
    }
}