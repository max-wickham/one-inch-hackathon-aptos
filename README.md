# Aptos Integration Of 1Inch Fusion Plus

This repository contains an implementation of the 1Inch Fusion Plus protocol in Aptos, maintaining the following features:

- Gasless user transactions:
    - Can be achieved easily using aptos gas sponsoring.
- Resovler payment of incentive fees. 
    - Achieved using Aptos multi agent transactions.
- Single order Escrow src and Dst
    - Allows for the deployment of Escrow contracts locking either user funds or relay funds. 
- Fusion Plus hashlock and timelock.
- Multi fill orders using merkle proofs. 

Due to the design of Aptos much of the complexity in the solidity implementation can be avoided. Aptos gas sponsoring allows users to sign transactions which resolvers can then submit on chain, paying for the gas. Multi agent transactions alson allow for both users and resolvers to move funds in a single transaction without Permit like solutions. This means that users can lock funds in the same transaction that resolvers provide incentive fees. 

## Aptos Dir

The aptos dir contains the order protocol implementation. There is also a basic test suite and move scripts to help with deploying mock tokens. 

The move implementation is based around two objects `Order` and `Escrow`. The order is similar to the LOP in the solidity implementation. When a user submits an order its make deposit is locked in this object along with a recovery fee from the resolver. The recovery fee is payed to the resolver that recovers funds after a set period of time or back to the original resolver in the case of an order being filled. The user also submits timelock parameters and a hashlock, (that optionally can be the state root of a merkle tree). The user also provided the token type for deposit and incentive fees, along with a whitelist.

When filling an order with Aptos as the source chain, the resolver call a function that creates an `Escrow` object, with the respective amount fo the users funds. The escrow must also hold a incentive fee of a minimum defined by the user. The escrow uses the hashlock set in the order, or if multi fill is enabled and the resolver provides a leaf and merkle proof of inclusion of the leaf in the order hashlock, the leaf will be used as the hashlock. 

Deployments of Escrow dst objects is entirely done directly by the resolver. The escrow dst uses the same object as the escrow src and if desired can set incentive fee to 0 and public cancellation time to effectively infinity to mimic the dst escrow in solidity. 

All the same cancellation and withdrawal functionality is provided on escrows as the solidity implementation. NOTE that only one cancellation and withdraw method are provided with the public and normal timelock period checked within these functions, thus implementation the functionality of both methods in the solidity implementation. 

A basic test suite is provided, (does not cover all functionality), that tests the basic flow of orders and escrows.
To run tests use the following command:

```bash
aptos move test --named-addresses escrow_factory=default
```

## Eth Dir

The eth dir contains a mock resolver contract designed to interact with the LOP and EscrowFactory contracts. This resolver has several utility methods to make construction of necessary objects easier in testing and is designed solely for making testing easier, not for actual use. 
Since the focus is on the Aptos implementation the minimum required to get working orders on Ethereum has been provided. 

Scripts for deploying the LOP, Factory, Resolver and mock tokens are also provided. 

## Relay Dir

The relay dir contains a basic TS script for testing transfers from Ethereum to Aptos or Aptos to Ethereum. For it to be used a .env file must be created with the necessary deployment addresses and private keys. 

The test script demonstrates the complete flow of escrow creation on both chains, and then unlocking of the contracts. When going from Aptos to Ethereum multi fill orders are used in order to demonstrate this functionality. 

Mock tokens are used on both chains for the swaps. (And fungible assets on Aptos could be used).