// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.23;

// import {console2 as console} from "forge-std@v1/src/console2.sol";
// import {IOrderMixin} from "limit-order-protocol@4/interfaces/IOrderMixin.sol";
// import {MakerTraitsLib} from
//     "limit-order-protocol@4/libraries/MakerTraitsLib.sol";
// import {
//     Address,
//     AddressLib
// } from "solidity-utils/contracts/libraries/AddressLib.sol";
// import {ERC20Permit} from
//     "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

// type MakerTraits is uint;

// type Timelocks is uint;

// struct Order {
//     uint salt;
//     Address maker;
//     Address receiver;
//     Address makerAsset;
//     Address takerAsset;
//     uint makingAmount;
//     uint takingAmount;
//     MakerTraits makerTraits;
// }

// interface IBaseEscrow {
//     struct Immutables {
//         bytes32 orderHash;
//         bytes32 hashlock; // Hash of the secret.
//         Address maker;
//         Address taker;
//         Address token;
//         uint amount;
//         uint safetyDeposit;
//         Timelocks timelocks;
//     }

//     /* solhint-disable func-name-mixedcase */
//     /// @notice Returns the delay for rescuing funds from the escrow.
//     function RESCUE_DELAY() external view returns (uint);
//     /// @notice Returns the address of the factory that created the escrow.
//     function FACTORY() external view returns (address);
//     /* solhint-enable func-name-mixedcase */

//     function withdraw(bytes32 secret, Immutables calldata immutables)
//         external;

//     function cancel(Immutables calldata immutables) external;

//     function rescueFunds(
//         address token,
//         uint amount,
//         Immutables calldata immutables
//     ) external;
// }

// interface IEscrowFactory {
//     struct ExtraDataArgs {
//         bytes32 hashlockInfo; // Hash of the secret or the Merkle tree root if multiple fills are allowed
//         uint dstChainId;
//         Address dstToken;
//         uint deposits;
//         Timelocks timelocks;
//     }

//     /* solhint-disable func-name-mixedcase */
//     /// @notice Returns the address of implementation on the source chain.
//     function ESCROW_SRC_IMPLEMENTATION() external view returns (address);
//     /// @notice Returns the address of implementation on the destination chain.
//     function ESCROW_DST_IMPLEMENTATION() external view returns (address);
//     /* solhint-enable func-name-mixedcase */

//     function createDstEscrow(
//         IBaseEscrow.Immutables calldata dstImmutables,
//         uint srcCancellationTimestamp
//     ) external payable;

//     function addressOfEscrowSrc(IBaseEscrow.Immutables calldata immutables)
//         external
//         view
//         returns (address);

//     function addressOfEscrowDst(IBaseEscrow.Immutables calldata immutables)
//         external
//         view
//         returns (address);
// }

// interface IBaseExtension {
//     function postInteraction(
//         Order calldata order,
//         bytes calldata extension,
//         bytes32 orderHash,
//         address taker,
//         uint makingAmount,
//         uint takingAmount,
//         uint remainingMakingAmount,
//         bytes calldata extraData
//     ) external;
// }

// contract MockLimitOrder {
//     using AddressLib for Address;
//     // using MakerTraitsLib for MakerTraits;

//     address public relay;

//     constructor(address relay_) {
//         relay = relay_;
//     }

//     modifier onlyRelay() {
//         require(msg.sender == relay, "Not authorized");
//         _;
//     }

//     mapping(bytes32 => bool) public existingOrders;

//     function submitMakeOrder(
//         address escrowFactory,
//         bytes32 hashLockInfo,
//         Address makerAsset,
//         Address takerAsset,
//         Address maker,
//         Address taker,
//         uint totalMakingAmount,
//         uint totalTakingAmount,
//         uint takingAmount,
//         uint timelock,
//         // Persmission sig to give access to this address to transfer funds from maker asset.
//         uint8 v,
//         bytes32 r,
//         bytes32 s,
//         uint deadline
//     ) external onlyRelay returns (address) {
//         // Mock implementation for order submission
//         Order memory order = Order({
//             salt: 0,
//             maker: maker,
//             receiver: taker,
//             makerAsset: makerAsset,
//             takerAsset: takerAsset,
//             makingAmount: 0,
//             takingAmount: 0,
//             makerTraits: MakerTraits.wrap(0) // MakerTraits.wrap(uint(1 << 255))
//         });

//         bytes32 orderHash = keccak256(abi.encode(order)); // Not actually used.

//         address makerAddress = address(uint160(Address.unwrap(maker)));
//         ERC20Permit token =
//             ERC20Permit(address(uint160(Address.unwrap(makerAsset))));
//         if (!existingOrders[orderHash]) {
//             // TODO transfer to srcEscrow
//             token.permit(
//                 makerAddress,
//                 address(this),
//                 totalMakingAmount,
//                 deadline,
//                 v,
//                 r,
//                 s
//             );
//         }

//         bytes memory extension = new bytes(0); // Mock extension data, not used.
//         // Remain amount calculation.
//         uint remainingTakingAmount = totalTakingAmount - takingAmount;
//         uint makingAmount =
//             (totalMakingAmount * takingAmount) / totalTakingAmount;
//         uint remainingMakingAmount = totalMakingAmount - makingAmount;

//         IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
//             orderHash: orderHash, // Not actually used.
//             hashlock: hashLockInfo,
//             maker: maker,
//             taker: taker,
//             token: makerAsset,
//             amount: totalMakingAmount,
//             safetyDeposit: 0, // Mock safety deposit
//             timelocks: Timelocks.wrap(timelock + ((block.timestamp) << 224)) // Mock timelocks
//         });
//         address srcEscrow =
//             IEscrowFactory(escrowFactory).addressOfEscrowSrc(immutables);
//         token.transferFrom(makerAddress, srcEscrow, makingAmount);

//         bytes memory extraData = abi.encode(
//             IEscrowFactory.ExtraDataArgs({
//                 hashlockInfo: hashLockInfo, // Mock hashlock info
//                 dstChainId: 0, // Mock destination chain ID
//                 dstToken: Address.wrap(uint(0)), // Mock destination token
//                 deposits: 0, // Mock deposits
//                 timelocks: Timelocks.wrap(timelock + ((block.timestamp) << 224)) // Mock timelocks
//             })
//         );

//         // TODO submit the interaction to the resolver.
//         address takerAddress = address(uint160(Address.unwrap(taker)));
//         IBaseExtension(escrowFactory).postInteraction(
//             order,
//             extension,
//             orderHash,
//             takerAddress,
//             makingAmount,
//             takingAmount,
//             remainingMakingAmount,
//             extraData
//         );

//         return srcEscrow;
//     }
// }