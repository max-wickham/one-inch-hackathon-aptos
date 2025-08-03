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
/* 
 * Basic Script to deploy the Resolver contract and its dependencies.
 * It also mints tokens and sets up permissions for the resolver and factory.
 * The script assumes the existence of a user and a relay caller address.
**/
contract ResolverScript is Script {
    function run() external {
        address user = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        // address relayCaller = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address relayCaller = 0x6c4f12827fFC1398aE4a794fe51471fdc2A098D2;
        
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
