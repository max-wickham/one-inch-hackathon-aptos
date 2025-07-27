// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
import {console2 as console} from "forge-std/console2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {TakerTraits, TakerTraitsLib} from "./libs/TakerTraitsLib.sol";
import {ExtensionsLib} from "./libs/ExtensionsLib.sol";
import {MakerTraitsLib, MakerTraits} from "./libs/MakerTraitsLib.sol";
// type MakerTraits is uint;
type Timelocks is uint;
// type TakerTraits is uint;
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

    function hashOrder(IOrderMixin.Order calldata order) external pure returns (bytes32);
}

contract Resolver is Ownable {
    using TakerTraitsLib for TakerTraits;
    using ExtensionsLib for bytes;

    address private immutable _LOP;
    address private immutable _Factory;

    constructor(
        address lop,
        address factory,
        address initialOwner
    ) Ownable(initialOwner) {
        _LOP = lop;
        _Factory = factory;
    }

    function getExtensions(
        IEscrowFactory.ExtraDataArgs calldata extraDataArgs,
        bytes memory permit
    ) public returns (bytes memory) {
        // limit-order-settlement/contracts/extensions/ResolverValidationExtension.sol
        // limit-order-settlement/contracts/extensions/ExtensionsLib.sol
        uint8 resolversCount = 1; // Only one resolver is allowed for now
        resolversCount <<= 3;
        console.log("resolversCount");
        console.log(resolversCount);
        uint80 resolverAddressMasked = uint80(uint160(address(this)));
        bytes memory resolverExtraData = abi.encodePacked(
            uint32(block.timestamp - 1 hours),
            resolverAddressMasked,
            uint16(0), // No time delta
            // new bytes(15),
            resolversCount
        );
        console.log("Resolver.getExtensions");
        console.logBytes( abi.encodePacked(resolverExtraData));
        // 0x00000e11a386870a03bc70d1b069759808
        // 0x00000e11a386870a03bc70d1b069759808
        return ExtensionsLib.newExtensions(
            new bytes(0), // No Maker Asset suffix
            new bytes(0), // No Taker Asset suffix
            new bytes(0), // No Making Amount Data
            abi.encodePacked(address(this)), // No Taking Amount Data
            new bytes(0), // No Predicate
            permit, // Maker Permit
            new bytes(0), // No Maker Asset Permit
            abi.encodePacked(_Factory, abi.encodePacked(resolverExtraData,abi.encode(extraDataArgs))),
            new bytes(0) // No Custom Data
        );
    }
    function deploySrc(
        IBaseEscrow.Immutables calldata immutables,
        IOrderMixin.Order calldata order, // Must set valid extension, Must set is allowed sender
        uint8 v, // Signature of the order
        bytes32 r,
        bytes32 s,
        uint amount,
        bytes calldata permit, // Permit the making amount to the OrderMixin for the token type
        IEscrowFactory.ExtraDataArgs calldata extraDataArgs
    )
        external
        payable
        onlyOwner
        returns (address)
    {
        IBaseEscrow.Immutables memory immutablesMem = immutables;

        // Set the timelock deployed at value
        uint timelock_uint = Timelocks.unwrap(immutablesMem.timelocks);
        timelock_uint = timelock_uint | (block.timestamp << 224);
        immutablesMem.timelocks = Timelocks.wrap(timelock_uint);

        // Compute the escrow address
        address escrow = IEscrowFactory(_Factory).addressOfEscrowSrc(
            immutablesMem
        );

        // Transfer the safety deposit to the escrow
        (bool success, ) = address(escrow).call{
            value: immutablesMem.safetyDeposit
        }("");
        require(success, "Transfer failed");

        bytes memory extensions = getExtensions(extraDataArgs, permit);

        bytes memory args = abi.encodePacked(
            address(escrow), // Target
            extensions // Extension
        );

        TakerTraits takerTraits = TakerTraitsLib.createTakerTraits(
            true, // hasTarget
            extensions.length, // extension length
            0 // interaction length
        );

        bytes32 vs = bytes32((uint256(v - 27) << 255)) | s;
        // Call the fillOrderArgs function on the LOP contract
        (uint256 makingAmount, uint256 takingAmount, bytes32 orderHash) = IOrderMixin(_LOP).fillOrderArgs(
            order,
            r,
            vs,
            amount,
            takerTraits,
            args
        );

        return escrow;
    }

    function getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external view returns (uint256) {
        // Always return 0 as the taking amount since the order is filled on another chain.
        return 1;
    }
}
