// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.23;

// import {Test} from "forge-std@v1/src/Test.sol";
// import {console2 as console} from "forge-std@v1/src/console2.sol";
// import {Vm} from "forge-std@v1/src/Vm.sol";
// import {
//     MockLimitOrder,
//     Timelocks,
//     Address,
//     IEscrowFactory,
//     IBaseEscrow
// } from "../src/MockLimitOrder.sol";
// import {ERC20Permit} from
//     "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
// import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import {EscrowFactory} from "cross-chain-swap@1/EscrowFactory.sol";

// // enum Stage {
// //         SrcWithdrawal,
// //         SrcPublicWithdrawal,
// //         SrcCancellation,
// //         SrcPublicCancellation,
// //         DstWithdrawal,
// //         DstPublicWithdrawal,
// //         DstCancellation
// //     }
// contract MockLimitOrderTest is Test {
//     // Vm vm = Vm(VM_ADDRESS);
//     function test_createSrcEscrow_Full() public {
//         MockLimitOrder mockLimitOrder = new MockLimitOrder(address(this));
//         MockPermitToken token = new MockPermitToken();
//         EscrowFactory factory = new EscrowFactory(
//             address(mockLimitOrder),
//             token,
//             token,
//             address(this),
//             30 minutes, // srcRescueDelay
//             30 minutes // dstRescueDelay
//         );
//         // TODO create EscrowFactory

//         uint makeAmount = 1 ether;
//         bytes32 secret = keccak256(abi.encodePacked("secret"));
//         bytes32 hashlock = keccak256(abi.encodePacked(secret));
//         // TODO timelock
//         uint32 srcWithdrawalDelay = 5 minutes;
//         uint32 srcPublicWithdrawalDelay = 10 minutes;
//         uint32 srcCancellationDelay = 15 minutes;
//         uint32 srcPublicCancellationDelay = 20 minutes;
//         uint32 dstWithdrawalDelay = 5 minutes;
//         uint32 dstPublicWithdrawalDelay = 10 minutes;
//         uint32 dstCancellationDelay = 14 minutes; // Should be less than srcCancellation
//         Timelocks timelock = Timelocks.wrap(
//             uint(srcWithdrawalDelay) | (uint(srcPublicWithdrawalDelay) << 32)
//                 | (uint(srcCancellationDelay) << 64)
//                 | (uint(srcPublicCancellationDelay) << 96)
//                 | (uint(dstWithdrawalDelay) << 128)
//                 | (uint(dstPublicWithdrawalDelay) << 160)
//                 | (uint(dstCancellationDelay) << 192)
//         );

//         // TODO extraArgs
//         IEscrowFactory.ExtraDataArgs memory extraDataArgs = IEscrowFactory
//             .ExtraDataArgs({
//             hashlockInfo: hashlock,
//             dstChainId: 0, // Mock destination chain ID
//             dstToken: Address.wrap(uint(0)), // Mock destination token
//             deposits: 0, // Mock deposits
//             timelocks: timelock
//         });

//         // Make a fake spender wallet
//         Vm.Wallet memory maker = vm.createWallet("maker");
//         token.transfer(maker.addr, makeAmount);

//         // Construct Permit
//         (uint8 v, bytes32 r, bytes32 s) = _constructPermit(
//             token,
//             maker.addr,
//             address(mockLimitOrder),
//             makeAmount,
//             block.timestamp + 1 hours,
//             maker.privateKey
//         );

//         // Taker amount
//         uint takeAmount = makeAmount;

//         address escrowSrc = mockLimitOrder.submitMakeOrder(
//             address(factory),
//             hashlock,
//             Address.wrap(uint(uint160(address(token)))), // maker token
//             Address.wrap(0), // take token
//             Address.wrap(uint(uint160(address(maker.addr)))), // maker
//             Address.wrap(0), // taker
//             makeAmount, // totalMakingAmount
//             takeAmount, // totalTakeAmount
//             takeAmount, // takingAmount
//             Timelocks.unwrap(timelock), // timelock
//             v,
//             r,
//             s,
//             block.timestamp + 1 hours
//         );

//         console.log(token.balanceOf(escrowSrc));

//         assertEq(
//             token.balanceOf(escrowSrc),
//             makeAmount,
//             "Escrow should have the correct balance"
//         );
//     }

//     function _constructPermit(
//         ERC20Permit token,
//         address owner,
//         address spender,
//         uint value,
//         uint deadline,
//         uint ownerPrivateKey
//     ) internal returns (uint8, bytes32, bytes32) {
//         uint nonce = token.nonces(owner);

//         // Get the domain separator
//         bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

//         // Construct the permit struct hash
//         bytes32 structHash = keccak256(
//             abi.encode(
//                 keccak256(
//                     "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
//                 ),
//                 owner,
//                 spender,
//                 value,
//                 nonce,
//                 deadline
//             )
//         );

//         // EIP-712 digest
//         bytes32 digest =
//             keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

//         // Sign the digest with the owner's private key
//         (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
//         return (v, r, s);
//     }
// }

// contract MockPermitToken is ERC20Permit {
//     constructor() ERC20("MyPermitToken", "MPT") ERC20Permit("MyPermitToken") {
//         _mint(msg.sender, 1000000 * 10 ** decimals());
//     }
// }
