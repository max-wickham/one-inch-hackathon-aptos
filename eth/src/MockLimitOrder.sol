// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IOrderMixin} from "limit-order-protocol@4/interfaces/IOrderMixin.sol";
import {MakerTraitsLib} from "limit-order-protocol@4/libraries/MakerTraitsLib.sol";
import {IEscrowFactory} from "cross-chain-swap@1/interfaces/IEscrowFactory.sol";
import {Address, AddressLib} from "solidity-utils/contracts/libraries/AddressLib.sol";

type MakerTraits is uint256;

struct Order {
    uint256 salt;
    Address maker;
    Address receiver;
    Address makerAsset;
    Address takerAsset;
    uint256 makingAmount;
    uint256 takingAmount;
    MakerTraits makerTraits;
}

struct ExtraDataArgs {
    bytes32 hashlockInfo; // Hash of the secret or the Merkle tree root if multiple fills are allowed
    uint256 dstChainId;
    Address dstToken;
    uint256 deposits;
    uint timelocks;
}

contract MockLimitOrder {
    using AddressLib for Address;
    // using MakerTraitsLib for MakerTraits;

    address public relay;

    constructor(address relay_) {
        relay = relay_;
    }

    modifier onlyRelay() {
        require(msg.sender == relay, "Not authorized");
        _;
    }

    function submitMakeOrder(
        bytes32 hashLockInfo,
        Address makerAsset,
        Address takerAsset,
        Address maker,
        Address taker,
        uint makingAmount,
        uint totalTakingAmount,
        uint takingAmount

    ) external onlyRelay {
        // Mock implementation for order submission
        Order memory order = Order({
            salt: 0,
            maker: maker,
            receiver: taker,
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            makingAmount: 0,
            takingAmount: 0,
            makerTraits: MakerTraits.wrap(uint(0))
        });

        bytes memory extension = new bytes(0); // Mock extension data, not used.

        bytes32 orderHash = keccak256(abi.encode(order)); // Not actually used.

        // Remain amount calculation.
        uint remainingTakingAmount = totalTakingAmount - takingAmount;

        bytes memory extraData = abi.encode(
            ExtraDataArgs({
                hashlockInfo: hashLockInfo, // Mock hashlock
                dstChainId: 0, // Mock destination chain ID
                dstToken: Address.wrap(uint(0)), // Mock destination token
                deposits: 0, // Mock deposits
                timelocks: 0 // Mock timelocks
            })
        );
    }
}

// function postInteraction(
//         IOrderMixin.Order calldata order,
//         bytes calldata extension,
//         bytes32 orderHash,
//         address taker,
//         uint256 makingAmount,
//         uint256 takingAmount,
//         uint256 remainingMakingAmount,
//         bytes calldata extraData
//     ) external onlyLimitOrderProtocol {
//         _postInteraction(order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData);
//     }




// TAKING AMOUNT CALC