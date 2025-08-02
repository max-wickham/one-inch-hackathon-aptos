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

import {IOrderMixin, IBaseEscrow, IBaseExtension, IEscrowFactory, Timelocks, Address} from "../src/OneInchInterfaces.sol";

contract MockPermitToken is ERC20Permit {
    constructor() ERC20("MyPermitToken", "MPT") ERC20Permit("MyPermitToken") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockPermitTakerToken is ERC20Permit {
    constructor()
        ERC20("MyPermitTakerToken", "MPTT")
        ERC20Permit("MyPermitTakerToken")
    {
        _mint(msg.sender, 100000000 ether);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ResolverTest is Test {
    function setUp() public {
        vm.warp(vm.getBlockTimestamp() + 100 hours);
    }

    function test_mockGetFunctions() public {
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

        uint takeAmount = 1;
        takerToken.transfer(address(resolver), 10000 ether);
        vm.prank(address(resolver));
        takerToken.approve(address(lop), type(uint256).max);

        bytes32 secret = keccak256(abi.encodePacked("secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));

        Timelocks timelocks = resolver.getDefaultTimelock(
            5 minutes, // srcWithdrawalDelay
            10 minutes, // srcPublicWithdrawalDelay
            15 minutes, // srcCancellationDelay
            20 minutes, // srcPublicCancellationDelay
            5 minutes, // dstWithdrawalDelay
            10 minutes, // dstPublicWithdrawalDelay
            14 minutes // dstCancellationDelay
        );

        IEscrowFactory.ExtraDataArgs memory extraDataArgs = resolver
            .getExtraDataArgs(hashlock, timelocks);

        bytes memory permit = _constructPermit(
            resolver,
            token,
            maker.addr,
            address(lop),
            makeAmount,
            block.timestamp + 1 hours,
            maker.privateKey
        );

        bytes memory extensions = resolver.getExtensions(extraDataArgs, permit);

        bytes32 extensionsHash = keccak256(extensions);

        IOrderMixin.Order memory order = resolver.getOrder(
            extensionsHash,
            maker.addr,
            address(token),
            address(takerToken),
            makeAmount
        );

        bytes32 orderHash = resolver.getOrderHash(order);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(maker.privateKey, orderHash);

        IBaseEscrow.Immutables memory immutables = resolver.getImmutables(
            orderHash,
            hashlock,
            maker.addr,
            address(token),
            makeAmount,
            timelocks
        );

        address escrow = resolver.deploySrc(
            order,
            v,
            r,
            s,
            immutables,
            makeAmount,
            permit,
            extraDataArgs
        );
        Timelocks newTimelocks = Timelocks.wrap(
            Timelocks.unwrap(timelocks) | (uint(block.timestamp) << 224)
        );
        IBaseEscrow.Immutables memory immutablesNew = resolver.getImmutables(
            orderHash,
            hashlock,
            maker.addr,
            address(token),
            makeAmount,
            newTimelocks
        );

        vm.warp(vm.getBlockTimestamp() + 5 minutes + 1 seconds);

        // Now make the withdrawal using the secret
        vm.prank(address(resolver));
        IBaseEscrow(escrow).withdraw(secret, immutablesNew);

        assertEq(token.balanceOf(address(resolver)), 1 ether);
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

        uint takeAmount = 1;
        takerToken.transfer(address(resolver), 10000 ether);
        vm.prank(address(resolver));
        takerToken.approve(address(lop), type(uint256).max);

        bytes32 secret = keccak256(abi.encodePacked("secret"));
        bytes32 hashlock = keccak256(abi.encodePacked(secret));
        // TODO timelock
        uint32 srcWithdrawalDelay = 1 minutes;
        uint32 srcPublicWithdrawalDelay = 10 minutes;
        uint32 srcCancellationDelay = 15 minutes;
        uint32 srcPublicCancellationDelay = 20 minutes;
        uint32 dstWithdrawalDelay = 1 minutes;
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
            resolver,
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
            makerTraits: MakerTraitsLib.newMakerTraits(
                address(0),
                block.timestamp + 60,
                false,
                true
            ) // MakerTraits.wrap(uint(1 << 255))
        });

        bytes32 orderHash = IOrderMixin(address(lop)).hashOrder(order);

        // Order sig
        // Permit
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(maker.privateKey, orderHash);

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

        address escrow = resolver.deploySrc(
            order,
            v,
            r,
            s,
            immutables,
            makeAmount,
            permit,
            extraDataArgs
        );
        vm.warp(vm.getBlockTimestamp() + 1 minutes + 1 seconds);

        // Now make the withdrawal using the secret
        vm.prank(address(resolver));
        IBaseEscrow(escrow).withdraw(secret, immutables);

        assertEq(token.balanceOf(address(resolver)), 1 ether);
    }

    function _constructPermit(
        Resolver resolver,
        ERC20Permit token,
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint ownerPrivateKey
    ) internal returns (bytes memory) {
        bytes32 digest = resolver.getPermitDigest(
            address(token),
            owner,
            spender,
            value,
            deadline
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        return resolver.packSig(v, r, s, address(token), value, deadline);
    }
}
