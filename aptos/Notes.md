```solidity
// Resolver's execution flow
contract Resolver {
    function executeCrossChainSwap(
        Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount
    ) external {
        // 1. Get future escrow address before filling order
        address futureEscrow = escrowFactory.addressOfEscrowSrc(
            order.hash(),
            block.chainid,
            destinationChainId,
            order.maker,
            address(this)
        );

        // 2. Send safety deposit to future escrow address
        payable(futureEscrow).transfer(safetyDepositAmount);


        // ???? How are these args created 
        // 3. Fill the order which creates the escrow via preInteraction
        limitOrderProtocol.fillOrderArgs(
            order,
            r,
            vs,
            amount,
            takerTraits,
            args
        );

        // 4. Verify escrow was created and funded
        require(IERC20(order.makerAsset).balanceOf(futureEscrow) >= order.makingAmount);

        // 5. Create corresponding destination escrow
        createDestinationEscrow(order.hash(), destinationChainId);
    }
}
```

- Work out how args created on limit order protocol fillOrderArgs

- Make mock limit order protocol for ethereum and for aptos??



Monday: Mock order limit protocol for Ethereum and Aptos
Tuesday: Escrow contracts on Aptos
Wednesday: Mock relay working on Eth
Thursday: Mock relay working on Aptos
Friday/ Weekend : UI, Get working on sui


```

User deposits funds to Order Limit Mock

Relay Creates escrow using signed mock 

Order must call post interaction on factory, do this by using the post interaction field. 

Factory will create escrow. 

```solidity
function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external onlyLimitOrderProtocol {
        _postInteraction(order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData);
    }

```


1. Maker signs transfer from limit order protocol to escrow address, with post action to init deterministic address,
2. Taker sends safety deposit to escrow address,
3. Taker fills order, which calls postInteraction on factory, creating the escrow address 

Taker creates allowance for factory contract and then create DstContract

Relay detects the creation of the dst creation even and then tells maker that it can reveal the secret

Maker optionally checks the addresses of the escrow and the destination and if valid 


Takes submits signed transaction to limit order protocol, which


## Move implementation

Taker is the one who owns the state of the escrow 

Eth -> Aptos

taker: Has a dict of dst srcs

1. Hash the parameters of the escrow to create an ID
2. At the ID in a map, store the tokens and the parameters of the escrow
3. Provide withdraw / cancel etc. functions based on the ID

Aptos -> Eth

Maker has contracts in LimitOrder contract. 

Need to provide function to check balance and to transfer funds to the escrow contract at makers address

Taker provides limit order, which includes additional parameters, which will call the escrow contract with the correct data

Taker provides parameters, signed by the maker 

Tokens are stored at takers address, at ID of parameters using dst contract

Withdraw function / Cancel functions using timelock 


Tasks:

Test that can create Escrow Src on ETH
Test that can create Escrow Dst on ETH

Implement mock token on Aptos
Implement Escrow on Aptos (No need for limit order can implement directly into aptos)
Test that can create Escrow Src on Aptos
Test that can create Escrow Dst on Aptos

Implement Mock Relay in python

Implement Mock Solver in python

Connect to Mock relay in python
Connect to Mock solver in python


{
    "limit order": object (eth),
    "aptos_tx": object,
    "
}


## Sep addresses 

limitOrderProtocol ME
feeToken 0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323
accessToken 0x5f207d42F869fd1c71d7f0f81a2A67Fc20FF7323
owner ME
rescueDelaySrc 120
rescueDelayDst 120


`forge create contracts/EscrowFactory.sol:EscrowFactory --private-key $PRIVATE_KEY --broadcast  --constructor-args $ME $WETH $WETH $ME 12`



## 
FillOrderArgs


// module escrow_addr::escrow_src {
//     use std::error;
//     use std::signer;
//     use std::string;
//     use aptos_framework::event;
//     #[test_only]
//     use std::debug;

//     // //:!:>resource
//     // struct MessageHolder has key {
//     //     message: string::String,
//     // }

// //   struct Immutables {
// //         bytes32 orderHash;
// //         bytes32 hashlock;  // Hash of the secret.
// //         Address maker;
// //         Address taker;
// //         Address token;
// //         uint256 amount;
// //         uint256 safetyDeposit;
// //         Timelocks timelocks;
// //     }


// //    SrcWithdrawal,
// //         SrcPublicWithdrawal,
// //         SrcCancellation,
// //         SrcPublicCancellation,
// //         DstWithdrawal,
// //         DstPublicWithdrawal,
// //         DstCancellation

//     struct Timelocks {
//         deployTimeStamp: u32, // Timestamp of the order deployment.
//         dstWithdrawTimePeriod: u32, // Time period for private withdrawal.
//         dstPublicWithdrawTimePeriod: u32, // Time period for public withdrawal.
//         srcWithdrawTimePeriod: u32, // Time period for private withdrawal.
//         srcPublicWithdrawTimePeriod: u32, // Time period for public withdrawal.
//         dstCancellationTimePeriod: u32, // Time period for private cancellation.
//         dstPublicCancellationTimePeriod: u32, // Time period for public cancellation.
//         srcCancellationTimePeriod: u32, // Time period for private cancellation.
//         srcPublicCancellationTimePeriod: u32, // Time period for public cancellation.
//     }

//     struct Immutables {
//         order_hash: vector<u8>,
//         hashlock: vector<u8>, // Hash of the secret.
//         maker: address,
//         taker: address,
//         token: address,
//         amount: u64,
//         safety_deposit: u64,
//         timelocks: Timelocks,
//     }

//     struct EscrowSrcState has key {
//         rescueDelay: u32, // Delay before the rescue can be executed.
//         // TODO access token
//     }

//     // Taker runs transaction on behalf of Maker (signer)
//     public entry fun create_src(account: Signer) {
//         // Create new EscrowSrc contract
//         // - Maker Address
//         // - Taker Address
//         // - Secret 
//         // - Tokens
//         // - Timelock
//         // Move escrowSrc to Taker Address escrowSrc Map
//     }

//     // TODO validate src (used be maker to check dst correct)

//     // Taker (signer) runs transaction 
//     public entry fun create_dst(account: Signer) {
//         // Create new EscrowDST
//         // - Maker Address
//         // - Taker Address
//         // - Secret
//         // - Tokens
//         // - Timelock
//         // Move escrowDst to Taker escrowDst Map
//     }

//     // TODO validate DST (used by maker to check dst correct)

//     // Anyone (signer)
//     public entry fun withdraw_src(account: Signer) {
//         // Find the escrowSrc in taker dict
//         // Reveal secret
//         // Check timelock
//         // Send funds to Taker
//     }

//     // Anyone (signer)
//     public entry fun withdraw_dst(account: Signer) {
//         // Find the escrowDst in taker dict
//         // Reveal secret
//         // Check timelock
//         // Send fund to Maker
//     }

//     // TODO timelock contracts etc.



//     // #[event]
//     // struct MessageChange has drop, store {
//     //     account: address,
//     //     from_message: string::String,
//     //     to_message: string::String,
//     // }

//     /// There is no message present
//     const ENO_MESSAGE: u64 = 0;

//     #[view]
//     public fun get_message(addr: address): string::String acquires MessageHolder {
//         assert!(exists<MessageHolder>(addr), error::not_found(ENO_MESSAGE));
//         borrow_global<MessageHolder>(addr).message
//     }

//     public entry fun set_message(account: signer, message: string::String)
//     acquires MessageHolder {
//         let account_addr = signer::address_of(&account);
//         if (!exists<MessageHolder>(account_addr)) {
//             move_to(&account, MessageHolder {
//                 message,
//             })
//         } else {
//             let old_message_holder = borrow_global_mut<MessageHolder>(account_addr);
//             let from_message = old_message_holder.message;
//             event::emit(MessageChange {
//                 account: account_addr,
//                 from_message,
//                 to_message: copy message,
//             });
//             old_message_holder.message = message;
//         }
//     }

//     #[test(account = @0x1)]
//     public entry fun sender_can_set_message(account: signer) acquires MessageHolder {
//         let msg: string::String = string::utf8(b"Running test for sender_can_set_message...");
//         debug::print(&msg);

//         let addr = signer::address_of(&account);
//         aptos_framework::account::create_account_for_test(addr);
//         set_message(account, string::utf8(b"Hello, Blockchain"));

//         assert!(
//             get_message(addr) == string::utf8(b"Hello, Blockchain"),
//             ENO_MESSAGE
//         );
//     }
// }