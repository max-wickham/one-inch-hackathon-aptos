// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;
import {Test} from "forge-std@v1/src/Test.sol";
import {console2 as console} from "forge-std@v1/src/console2.sol";
import {Vm} from "forge-std@v1/src/Vm.sol";
import {MakerTraitsLib, MakerTraits} from "../src/libs/MakerTraitsLib.sol";
import {Resolver, Timelocks, Address, IEscrowFactory, IBaseEscrow, IOrderMixin} from "../src/Resolver.sol";
import {IWETH} from "@1inch/solidity-utils/contracts/interfaces/IWETH.sol";

import {LimitOrderProtocol} from "limit-order-protocol@4/LimitOrderProtocol.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {EscrowFactory} from "cross-chain-swap@1/EscrowFactory.sol";

contract MockPermitToken is ERC20Permit {
    constructor() ERC20("MyPermitToken", "MPT") ERC20Permit("MyPermitToken") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract MockPermitTakerToken is ERC20Permit {
    constructor() ERC20("MyPermitTakerToken", "MPTT") ERC20Permit("MyPermitTakerToken") {
        _mint(msg.sender, 100000000 ether);
    }
}



contract ResolverTest is Test {

    // address constant PERMIT2 = address(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    function setUp() public {

        vm.warp(vm.getBlockTimestamp() + 100 hours);
    }


    function test_deploySrcEscrow() public {
        MockPermitToken token = new MockPermitToken();
        MockPermitTakerToken takerToken = new MockPermitTakerToken();
        LimitOrderProtocol lop = new LimitOrderProtocol(IWETH(address(token)));
        EscrowFactory factory = new EscrowFactory(
            address(lop),
            token,
            token,
            address(this),
            30 minutes, // srcRescueDelay
            30 minutes // dstRescueDelay
        );
        Resolver resolver = new Resolver(
            address(lop),
            address(factory),
            address(this)
        );

        uint makeAmount = 1 ether;
        Vm.Wallet memory maker = vm.createWallet("maker");
        token.transfer(maker.addr, makeAmount * 3);



        // Give the MockPermit2 contract unlimited allowance on the maker
        // vm.prank(maker.addr);
        // token.approve(PERMIT2, type(uint256).max);

        // Vm.Wallet memory taker = vm.createWallet("taker");


        uint takeAmount = 1;
        takerToken.transfer(address(resolver), 10000 ether);
        vm.prank(address(resolver));
        takerToken.approve(address(lop), type(uint256).max);

        bytes32 secret = keccak256(abi.encodePacked("secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        // TODO timelock
        uint32 srcWithdrawalDelay = 5 minutes;
        uint32 srcPublicWithdrawalDelay = 10 minutes;
        uint32 srcCancellationDelay = 15 minutes;
        uint32 srcPublicCancellationDelay = 20 minutes;
        uint32 dstWithdrawalDelay = 5 minutes;
        uint32 dstPublicWithdrawalDelay = 10 minutes;
        uint32 dstCancellationDelay = 14 minutes; // Should be less than srcCancellation
        Timelocks timelock = Timelocks.wrap(
            uint(srcWithdrawalDelay) |
                (uint(srcPublicWithdrawalDelay) << 32) |
                (uint(srcCancellationDelay) << 64) |
                (uint(srcPublicCancellationDelay) << 96) |
                (uint(dstWithdrawalDelay) << 128) |
                (uint(dstPublicWithdrawalDelay) << 160) |
                (uint(dstCancellationDelay) << 192) |
                (uint(block.timestamp) << 224)
        );

        IEscrowFactory.ExtraDataArgs memory extraDataArgs = IEscrowFactory
            .ExtraDataArgs({
                hashlockInfo: hashlock,
                dstChainId: 0, // Mock destination chain ID
                dstToken: Address.wrap(uint(0)), // Mock destination token
                deposits: 0, // Mock deposits
                timelocks: timelock
            });
        bytes memory permit = _constructPermit(
            token,
            maker.addr,
            address(lop),
            makeAmount,
            block.timestamp + 1 hours,
            maker.privateKey
        );
        console.logBytes(permit);

        bytes memory extensions = resolver.getExtensions(extraDataArgs, permit);
        bytes32 extensionsHash = keccak256(extensions);

        IOrderMixin.Order memory order = IOrderMixin.Order({
            salt: uint(uint160(uint(extensionsHash))),
            maker: Address.wrap(uint(uint160(maker.addr))),
            receiver: Address.wrap(uint(uint160(address(resolver)))),
            makerAsset: Address.wrap(uint(uint160(address(token)))),
            takerAsset: Address.wrap(uint(uint160(address(takerToken)))),
            makingAmount: makeAmount,
            takingAmount: 0,
            makerTraits: MakerTraitsLib.newMakerTraits(address(0), block.timestamp + 60, false, true) // MakerTraits.wrap(uint(1 << 255))
        });

        bytes32 orderHash = IOrderMixin(address(lop)).hashOrder(order);

        // Order sig
        // Permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            maker.privateKey,
            orderHash
        );

        IBaseEscrow.Immutables memory immutables = IBaseEscrow.Immutables({
            orderHash: orderHash, // Not actually used.
            hashlock: hashlock,
            maker: Address.wrap(uint(uint160(maker.addr))),
            taker: Address.wrap(uint(uint160(address(resolver)))),
            token: Address.wrap(uint(uint160(address(token)))),
            amount: makeAmount,
            safetyDeposit: 0, // Mock safety deposit
            timelocks: timelock
        });

        address escrow = resolver.deploySrc(immutables, order, v, r, s, makeAmount, permit, extraDataArgs);
        vm.warp(vm.getBlockTimestamp() + 5 minutes + 1 seconds);

        // Now make the withdrawal using the secret
        vm.prank(address(resolver));
        IBaseEscrow(escrow).withdraw(
            secret,
            immutables
        );

        assertEq(token.balanceOf(address(resolver)), 1 ether);
    }

    function _constructPermit(
        ERC20Permit token,
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint ownerPrivateKey
    ) internal returns (bytes memory) {
        uint nonce = token.nonces(owner);

        // Get the domain separator
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();

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

        // Sign the digest with the owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        uint256 vs = (uint256(v - 27) << 255) | uint256(s);
        return abi.encodePacked(token, value, uint32(deadline), r, vs);

    }
}
