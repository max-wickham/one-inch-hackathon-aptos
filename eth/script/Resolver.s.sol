// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {console2 as console} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";

import {LimitOrderProtocol} from "limit-order-protocol@4/LimitOrderProtocol.sol";
import {IWETH} from "@1inch/solidity-utils/contracts/interfaces/IWETH.sol";
import {Resolver, Timelocks, Address, IEscrowFactory, IBaseEscrow, IOrderMixin} from "../src/Resolver.sol";
import {EscrowFactory} from "cross-chain-swap@1/EscrowFactory.sol";
import {ERC20Permit} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract ResolverScript is Script {
    function run() external {
        address user = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address relayCaller = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        
            vm.startBroadcast();
            MockPermitToken token = new MockPermitToken(msg.sender);
            MockPermitTakerToken takerToken = new MockPermitTakerToken(
                msg.sender
            );
            LimitOrderProtocol lop = new LimitOrderProtocol(
                IWETH(address(token))
            );
            EscrowFactory factory = new EscrowFactory(
                address(lop),
                token,
                token,
                msg.sender,
                30 minutes, // srcRescueDelay
                30 minutes // dstRescueDelay
            );
            Resolver resolver = new Resolver(
                address(lop),
                address(factory),
                msg.sender
            );
            vm.stopBroadcast();
        
        {
            console.log("RESOLVER_ADDRESS=", address(resolver));
            console.log("FACTORY_ADDRESS=", address(factory));
            console.log("LOP_ADDRESS=", address(lop));
            console.log("TOKEN_ADDRESS=", address(token));
            console.log("TAKER_TOKEN_ADDRESS=", address(takerToken));
        }
        {
            vm.startBroadcast();
            token.transfer(address(user), 1000000 ether);
            takerToken.transfer(address(resolver), 1000000 ether);
            token.transfer(address(resolver), 1000000 ether);
            token.permit(address(factory), address(resolver));
            token.permit(address(lop), address(user));
            takerToken.permit(address(lop), address(resolver));
            vm.stopBroadcast();
        }
    }
}

contract MockPermitToken is ERC20Permit {
    constructor(
        address minter
    ) ERC20("MyPermitToken", "MPT") ERC20Permit("MyPermitToken") {
        _mint(minter, 100000000 ether);
    }

    function permit(address spender, address owner) public {
        _approve(owner, spender, type(uint256).max, false);
    }
}

contract MockPermitTakerToken is ERC20Permit {
    constructor(
        address minter
    ) ERC20("MyPermitTakerToken", "MPTT") ERC20Permit("MyPermitTakerToken") {
        _mint(minter, 100000000 ether);
    }

    function permit(address spender, address owner) public {
        _approve(owner, spender, type(uint256).max, false);
    }
}

// contract ResolverOrderCreate is Script {

//     function run() external {

//         // Deploy all contract needed for the Resolver
//         // This includes the LimitOrderProtocol, EscrowFactory, and Resolver contracts
//         address resolver = 0x9ee0DC1f7cF1a5c083914e3de197Fd1F484E0578;
//         address factory = 0xBd640b5C2190372877346474c8a9aA7b8C871DF1;
//         uint makeAmount = 1 ether;
//         bytes32 secret = keccak256(abi.encodePacked("secret"));
//         bytes32 hashlock = keccak256(abi.encodePacked(secret));

//         uint32 srcWithdrawalDelay = 5 minutes;
//         uint32 srcPublicWithdrawalDelay = 10 minutes;
//         uint32 srcCancellationDelay = 15 minutes;
//         uint32 srcPublicCancellationDelay = 20 minutes;
//         uint32 dstWithdrawalDelay = 5 minutes;
//         uint32 dstPublicWithdrawalDelay = 10 minutes;
//         uint32 dstCancellationDelay = 14 minutes; // Should be less than srcCancellation
//         Timelocks timelock = Timelocks.wrap(
//             uint(srcWithdrawalDelay) |
//                 (uint(srcPublicWithdrawalDelay) << 32) |
//                 (uint(srcCancellationDelay) << 64) |
//                 (uint(srcPublicCancellationDelay) << 96) |
//                 (uint(dstWithdrawalDelay) << 128) |
//                 (uint(dstPublicWithdrawalDelay) << 160) |
//                 (uint(dstCancellationDelay) << 192) |
//                 (uint(block.timestamp) << 224)
//         );

//         IEscrowFactory.ExtraDataArgs memory extraDataArgs = IEscrowFactory
//             .ExtraDataArgs({
//                 hashlockInfo: hashlock,
//                 dstChainId: 0, // Mock destination chain ID
//                 dstToken: Address.wrap(uint(0)), // Mock destination token
//                 deposits: 0, // Mock deposits
//                 timelocks: timelock
//             });

//         bytes memory permit = _constructPermit(
//             token,
//             maker.addr,
//             address(lop),
//             makeAmount,
//             block.timestamp + 1 hours,
//             maker.privateKey
//         );
//         vm.startBroadcast();

//         // MockPermitToken token = new MockPermitToken(msg.sender);
//         // MockPermitTakerToken takerToken = new MockPermitTakerToken(msg.sender);
//         // LimitOrderProtocol lop = new LimitOrderProtocol(IWETH(address(token)));
//         // EscrowFactory factory = new EscrowFactory(
//         //     address(lop),
//         //     token,
//         //     token,
//         //     msg.sender,
//         //     30 minutes, // srcRescueDelay
//         //     30 minutes // dstRescueDelay
//         // );
//         // Resolver resolver = new Resolver(
//         //     address(lop),
//         //     address(factory),
//         //     msg.sender
//         // );

//         // token.transfer(address(resolver), 1000000 ether);
//         // takerToken.transfer(address(resolver), 1000000 ether);

//         // vm.stopBroadcast();
//         // console.log("Resolver deployed at:", address(resolver));
//         // console.log("Factory deployed at:", address(factory));
//         // console.log("LimitOrderProtocol deployed at:", address(lop));
//         // console.log("MockPermitToken deployed at:", address(token));
//         // console.log("MockPermitTakerToken deployed at:", address(takerToken));

//         // vm.startBroadcast();

//         // // Deploy the Resolver contract
//         // console.log("Resolver deployed at:", address(resolver));

//         vm.stopBroadcast();
//     }
// }
