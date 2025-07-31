// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
import {console2 as console} from "forge-std/console2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {TakerTraits, TakerTraitsLib} from "./libs/TakerTraitsLib.sol";
import {ExtensionsLib} from "./libs/ExtensionsLib.sol";
import {MakerTraitsLib, MakerTraits} from "./libs/MakerTraitsLib.sol";
import {IOrderMixin, IBaseEscrow, IBaseExtension, IEscrowFactory, Timelocks, Address} from "./OneInchInterfaces.sol";


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

    receive() external payable {} // solhint-disable-line no-empty-blocks

    function getExtensions(
        IEscrowFactory.ExtraDataArgs calldata extraDataArgs,
        bytes memory permit
    ) public returns (bytes memory) {
        // limit-order-settlement/contracts/extensions/ResolverValidationExtension.sol
        // limit-order-settlement/contracts/extensions/ExtensionsLib.sol
        uint8 resolversCount = 1; // Only one resolver is allowed for now.
        resolversCount <<= 3;
        uint80 resolverAddressMasked = uint80(uint160(address(this)));
        bytes memory resolverExtraData = abi.encodePacked(
            uint32(block.timestamp - 1 hours),
            resolverAddressMasked,
            uint16(0), // No time delta
            resolversCount
        );
        return
            ExtensionsLib.newExtensions(
                new bytes(0), // No Maker Asset suffix
                new bytes(0), // No Taker Asset suffix
                new bytes(0), // No Making Amount Data
                abi.encodePacked(address(this)), // No Taking Amount Data
                new bytes(0), // No Predicate
                permit, // Maker Permit
                new bytes(0), // No Maker Asset Permit
                abi.encodePacked(
                    _Factory,
                    abi.encodePacked(
                        resolverExtraData,
                        abi.encode(extraDataArgs)
                    )
                ),
                new bytes(0) // No Custom Data
            );
    }

    // These mock methods can be used to create the order configs
    
    // TODO get default timelock

    // TODO get extradata args

    // TODO get extensions hash

    // TODO get order/ order hash

    // TODO get immutables 


    function deploySrc(
        IBaseEscrow.Immutables calldata immutables,
        IOrderMixin.Order calldata order, // Must set valid extension, Must set is allowed sender
        uint8 v, // Signature of the order
        bytes32 r,
        bytes32 s,
        uint amount,
        bytes calldata permit, // Permit the making amount to the OrderMixin for the token type
        IEscrowFactory.ExtraDataArgs calldata extraDataArgs
    ) external payable onlyOwner returns (address) {

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

        // Compute the extensions
        bytes memory extensions = getExtensions(extraDataArgs, permit);

        // Compute the fill order args
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
        (
            uint256 makingAmount,
            uint256 takingAmount,
            bytes32 orderHash
        ) = IOrderMixin(_LOP).fillOrderArgs(
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
