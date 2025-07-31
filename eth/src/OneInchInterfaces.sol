// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {TakerTraits, TakerTraitsLib} from "./libs/TakerTraitsLib.sol";
import {ExtensionsLib} from "./libs/ExtensionsLib.sol";
import {MakerTraitsLib, MakerTraits} from "./libs/MakerTraitsLib.sol";

type Timelocks is uint;
type Address is uint;

interface IBaseEscrow {
    struct Immutables {
        bytes32 orderHash;
        bytes32 hashlock; // Hash of the secret.
        Address maker;
        Address taker;
        Address token;
        uint amount;
        uint safetyDeposit;
        Timelocks timelocks;
    }

    /* solhint-disable func-name-mixedcase */
    /// @notice Returns the delay for rescuing funds from the escrow.
    function RESCUE_DELAY() external view returns (uint);
    /// @notice Returns the address of the factory that created the escrow.
    function FACTORY() external view returns (address);
    /* solhint-enable func-name-mixedcase */

    function withdraw(bytes32 secret, Immutables calldata immutables) external;

    function cancel(Immutables calldata immutables) external;

    function rescueFunds(
        address token,
        uint amount,
        Immutables calldata immutables
    ) external;
}

interface IEscrowFactory {
    struct ExtraDataArgs {
        bytes32 hashlockInfo; // Hash of the secret or the Merkle tree root if multiple fills are allowed
        uint dstChainId;
        Address dstToken;
        uint deposits;
        Timelocks timelocks;
    }

    /* solhint-disable func-name-mixedcase */
    /// @notice Returns the address of implementation on the source chain.
    function ESCROW_SRC_IMPLEMENTATION() external view returns (address);
    /// @notice Returns the address of implementation on the destination chain.
    function ESCROW_DST_IMPLEMENTATION() external view returns (address);
    /* solhint-enable func-name-mixedcase */

    function createDstEscrow(
        IBaseEscrow.Immutables calldata dstImmutables,
        uint srcCancellationTimestamp
    ) external payable;

    function addressOfEscrowSrc(
        IBaseEscrow.Immutables calldata immutables
    ) external view returns (address);

    function addressOfEscrowDst(
        IBaseEscrow.Immutables calldata immutables
    ) external view returns (address);
}

interface IBaseExtension {
    function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint makingAmount,
        uint takingAmount,
        uint remainingMakingAmount,
        bytes calldata extraData
    ) external;
}

interface IOrderMixin {
    struct Order {
        uint salt;
        Address maker;
        Address receiver;
        Address makerAsset;
        Address takerAsset;
        uint makingAmount;
        uint takingAmount;
        MakerTraits makerTraits; // TODO set is allowed sender ??
    }

    function fillOrderArgs(
        IOrderMixin.Order calldata order,
        bytes32 r,
        bytes32 vs,
        uint256 amount,
        TakerTraits takerTraits,
        bytes calldata args
    )
        external
        payable
        returns (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash);

    function hashOrder(
        IOrderMixin.Order calldata order
    ) external pure returns (bytes32);
}