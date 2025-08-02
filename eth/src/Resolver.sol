// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
import {console2 as console} from "forge-std/console2.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {TakerTraits, TakerTraitsLib} from "./libs/TakerTraitsLib.sol";
import {ExtensionsLib} from "./libs/ExtensionsLib.sol";
import {MakerTraitsLib, MakerTraits} from "./libs/MakerTraitsLib.sol";
import {IOrderMixin, IBaseEscrow, IBaseExtension, IEscrowFactory, Timelocks, Address} from "./OneInchInterfaces.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
// import "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";

interface IResolver {
    function getOrderHashLocal(
        IOrderMixin.Order calldata order
    ) external view returns (bytes32);
}

contract Resolver is Ownable {
    // using SafeERC20 for IERC20;

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
        IEscrowFactory.ExtraDataArgs memory extraDataArgs,
        bytes memory permit
    ) public view returns (bytes memory) {
        // limit-order-settlement/contracts/extensions/ResolverValidationExtension.sol
        // limit-order-settlement/contracts/extensions/ExtensionsLib.sol
        uint8 resolversCount = 1; // Only one resolver is allowed for now.
        resolversCount <<= 3;
        uint80 resolverAddressMasked = uint80(uint160(address(this)));
        bytes memory resolverExtraData = abi.encodePacked(
            // Use a past timestamp to avoid having to wait
            uint32(1754125455),
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
    function getDefaultTimelock(
        // Timelocks timelocks
        uint32 srcWithdrawalDelay,
        uint32 srcPublicWithdrawalDelay,
        uint32 srcCancellationDelay,
        uint32 srcPublicCancellationDelay,
        uint32 dstWithdrawalDelay,
        uint32 dstPublicWithdrawalDelay,
        uint32 dstCancellationDelay
    ) public pure returns (Timelocks) {
        // Default timelock values
       
        return Timelocks.wrap(
            (uint(srcWithdrawalDelay) |
                (uint(srcPublicWithdrawalDelay) << 32) |
                (uint(srcCancellationDelay) << 64) |
                (uint(srcPublicCancellationDelay) << 96) |
                (uint(dstWithdrawalDelay) << 128) |
                (uint(dstPublicWithdrawalDelay) << 160) |
                (uint(dstCancellationDelay) << 192))
        );
    }

    // TODO get extradata args
    function getExtraDataArgs(
        bytes32 hashlockInfo,
        Timelocks timelocks
    ) public pure returns (IEscrowFactory.ExtraDataArgs memory) {
        return IEscrowFactory.ExtraDataArgs({
            hashlockInfo: hashlockInfo,
            dstChainId: 0, // Mock destination chain ID
            dstToken: Address.wrap(uint(0)), // Mock destination token
            deposits: 0, // Mock deposits
            timelocks: timelocks
        });
    }

    function getPermitDigest(
        address token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline
    ) public view returns (bytes32) {
        value = type(uint256).max; // Use max value for testing
        // Construct the permit digest
        // Get the domain separator
        bytes32 domainSeparator = ERC20Permit(token).DOMAIN_SEPARATOR();
        uint nonce = ERC20Permit(token).nonces(owner);
        // Construct the permit struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner,
                spender,
                value,
                nonce,
                deadline - 1
            )
        );

        // EIP-712 digest
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        return digest;
    }
    
    function getExtensionsHash(
        bytes memory extensions
    ) public pure returns (bytes32) {
        // Compute the hash of the extensions
        return keccak256(extensions);
    }

    function getOrder(
        bytes32 extensionsHash,
        address maker,
        address token,
        address mockTakerToken,
        uint makeAmount
    ) public view returns (IOrderMixin.Order memory) {
        // Construct the order
        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: uint(uint160(uint(extensionsHash))),
            maker: Address.wrap(uint(uint160(maker))),
            receiver: Address.wrap(uint(uint160(address(address(this))))),
            makerAsset: Address.wrap(uint(uint160(address(token)))),
            takerAsset: Address.wrap(uint(uint160(address(mockTakerToken)))),
            makingAmount: makeAmount,
            takingAmount: 0,
            makerTraits: MakerTraitsLib.newMakerTraits(address(0), block.timestamp + 60, false, true) // MakerTraits.wrap(uint(1 << 255))
        });
        return order;
    }

    function getOrderHashLocal(
        IOrderMixin.Order calldata order
    ) public view returns (bytes32) {
        console.log("getOrderHash called");
        return IOrderMixin(_LOP).hashOrder(order);
    }

    function getOrderHash(
        IOrderMixin.Order memory order
    ) public view returns (bytes32) {
        return IResolver(address(this)).getOrderHashLocal(order);
    }

    function getOrderAndHash(
        bytes32 extensionsHash,
        address maker,
        address token,
        address mockTakerToken,
        uint makeAmount
    ) public view returns (IOrderMixin.Order memory, bytes32) {
        // Get the order
        IOrderMixin.Order memory order = getOrder(
            extensionsHash,
            maker,
            token,
            mockTakerToken,
            makeAmount
        );
        // Get the order hash
        bytes32 hash = getOrderHash(order);
        return (order, hash);
    }

    function isValidOrderSig(
        IOrderMixin.Order memory order,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address signer
    ) public view returns (bool) {
        // Check if the order signature is valid
        bytes32 orderHash = getOrderHash(order);
        // Check if the signature is valid
        address maker = address(uint160(Address.unwrap(order.maker)));
        return maker == ecrecover(
            orderHash,
            v,
            r,
            s
        );
    }

    function getImmutables(
        bytes32 orderHash,
        bytes32 hashlock,
        address maker,
        address token,
        uint256 amount,
        Timelocks timelocks
    ) public view returns (IBaseEscrow.Immutables memory) {
        // Construct the immutables
        return IBaseEscrow.Immutables({
            orderHash: orderHash,
            hashlock: hashlock,
            maker: Address.wrap(uint160(maker)),
            taker: Address.wrap(uint160(address(this))),
            token: Address.wrap(uint160(token)),
            amount: amount,
            safetyDeposit: 0,
            timelocks: timelocks
        });
    }

    function packSig(uint8 v, bytes32 r, bytes32 s, address token, uint value, uint deadline)public view returns (bytes memory) {
        value = type(uint256).max; // Use max value for testing
        uint256 vs = (uint256(v - 27) << 255) | uint256(s);
        return abi.encodePacked(token, value, uint32(deadline), r, vs);
    }


    function deploySrc(
        IOrderMixin.Order memory order, // Must set valid extension, Must set is allowed sender
        uint8 v, // Signature of the order
        bytes32 r,
        bytes32 s,
        IBaseEscrow.Immutables memory immutables,
        uint amount,
        bytes memory permit, // Permit the making amount to the OrderMixin for the token type
        IEscrowFactory.ExtraDataArgs memory extraDataArgs
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
        console.logBytes( extensions);
                // Check the order salt is valid
        console.log("Order salt:", order.salt);
        console.logBytes32(keccak256(extensions) );
        require(
            order.salt == uint(uint160(uint(keccak256(extensions)))),
            "Invalid order salt"
        );
        

// f38ee1cdc13d5ecad3447499737790e633a360f8fdb7260b0416688dc41791ce7e993f18dffeb4f2000008290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000384000002580000012c000004b00000038400000258
// f38ee1cdc13d5ecad3447499737790e633a360f8fdb7260b0416688dc3fa91ce7e993f18dffeb4f2000008290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000384000002580000012c000004b00000038400000258
// 0x000001510000008c0000008c0000001400000014000000000000000000000000615e53e40cb4731d7ffb91ce7e993f18dffeb4f287850524d6390e713e556b9dae4c0eab3e93f89b000000000000000000000000000000000000000000000000000000003b9aca00688de03458477f3322e910033e80c4f8a4107e605766700eed7128a26590a1cc5ee66ed12a27a830ebfa5924d9a1b8b26350f97267e79eb2452965621ecff38ee1cdc13d5ecad3447499737790e633a360f8fdb7260b0416688dc41791ce7e993f18dffeb4f2000008290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000384000002580000012c000004b00000038400000258
// 0x000001510000008c0000008c0000001400000014000000000000000000000000615e53e40cb4731d7ffb91ce7e993f18dffeb4f287850524d6390e713e556b9dae4c0eab3e93f89b000000000000000000000000000000000000000000000000000000003b9aca00688de03458477f3322e910033e80c4f8a4107e605766700eed7128a26590a1cc5ee66ed12a27a830ebfa5924d9a1b8b26350f97267e79eb2452965621ecff38ee1cdc13d5ecad3447499737790e633a360f8fdb7260b0416688dc3fa91ce7e993f18dffeb4f2000008290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e5630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000384000002580000012c000004b00000038400000258 
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
        bytes32 orderHash_ = getOrderHash(order);

        // Validate the order signature
        address maker = address(uint160(Address.unwrap(order.maker)));
        if (!isValidOrderSig(order, v, r, s, maker)) {
            console.log(v);
            console.logBytes32(r);
            console.logBytes32(s);
            console.log("Invalid order signature");
            revert("Invalid order signature");
        }
        require(
            isValidOrderSig(order, v, r, s, maker),
            "Invalid order signature"
        );
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
