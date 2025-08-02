import {
    Aptos,
    AptosConfig,
    Network,
    Account,
    Ed25519PrivateKey,
    InputEntryFunctionData,
    AccountAddress,
    Uint8,
} from "@aptos-labs/ts-sdk";
import * as dotenv from "dotenv";
import { keccak256, SigningKey, toUtf8Bytes } from "ethers";
import { ethers, Contract, Wallet, Provider } from "ethers";
// Load environment variables
dotenv.config();

class AptosOrderManager {
    private aptos: Aptos;
    private userAccount: Account;
    private relayAccount: Account;
    private moduleAddress: string;

    constructor() {
        // Initialize Aptos client
        const network =
            (process.env.APTOS_NETWORK as Network) || Network.TESTNET;
        const config = new AptosConfig({ network });
        this.aptos = new Aptos(config);

        // Create accounts from private keys
        this.userAccount = this.createAccountFromPrivateKey(
            process.env.USER_PRIV_KEY!
        );
        this.relayAccount = this.createAccountFromPrivateKey(
            process.env.RELAY_PRIV_KEY!
        );

        this.moduleAddress = process.env.MODULE_ADDRESS!;
    }

    private createAccountFromPrivateKey(privateKeyHex: string): Account {
        // Remove '0x' prefix if present
        const cleanPrivateKey = privateKeyHex.startsWith("0x")
            ? privateKeyHex.slice(2)
            : privateKeyHex;

        const privateKey = new Ed25519PrivateKey(cleanPrivateKey);
        return Account.fromPrivateKey({ privateKey });
    }

    private generateSalt(): Uint8Array {
        // Generate random 8-byte salt
        const salt = new Uint8Array(8);
        crypto.getRandomValues(salt);
        return salt;
    }

    async createOrder(params: {
        depositAssetMetadata: string;
        incentive_feeAssetMetadata: string;
        recover_incentive_fee: number;
        recoverPeriod: number;
        deposit_amount: number;
        min_incentive_fee: number;
        // salt: Uint8Array;
        hashlock: Uint8Array;
        allow_multi_fill: boolean;
        whitelisted_addresses: string[];
        withDrawPeriod: number;
        publicWithDrawPeriod: number;
        cancelPeriod: number;
        publicCancelPeriod: number;
    }): Promise<{ transactionHash: string; orderAddress: string }> {
        try {
            console.log("Creating order transaction...");
            console.log(
                "User account:",
                this.userAccount.accountAddress.toString()
            );
            console.log(
                "Relay account:",
                this.relayAccount.accountAddress.toString()
            );

            // Build the transaction payload
            const payload: InputEntryFunctionData = {
                function: `${this.moduleAddress}::order_factory::create_order`,
                typeArguments: ["0x1::fungible_asset::Metadata"], // Replace with your asset type
                functionArguments: [
                    params.depositAssetMetadata,
                    params.incentive_feeAssetMetadata,
                    params.recover_incentive_fee,
                    params.recoverPeriod,
                    params.deposit_amount,
                    params.min_incentive_fee,
                    Array.from(this.generateSalt()), // Generate salt if not provided
                    Array.from(params.hashlock),
                    params.allow_multi_fill,
                    params.whitelisted_addresses,
                    params.withDrawPeriod,
                    params.publicWithDrawPeriod,
                    params.cancelPeriod,
                    params.publicCancelPeriod,
                ],
            };

            // Build the multi-agent transaction
            const transaction = await this.aptos.transaction.build.multiAgent({
                sender: this.relayAccount.accountAddress,
                secondarySignerAddresses: [this.userAccount.accountAddress],
                data: payload,
            });

            // Sign the transaction with both accounts
            const relayAuthenticator = this.aptos.transaction.sign({
                signer: this.relayAccount,
                transaction,
            });

            const userAuthenticator = this.aptos.transaction.sign({
                signer: this.userAccount,
                transaction,
            });

            // Submit the multi-agent transaction
            const committedTransaction =
                await this.aptos.transaction.submit.multiAgent({
                    transaction,
                    senderAuthenticator: relayAuthenticator,
                    additionalSignersAuthenticators: [userAuthenticator],
                });

            console.log("Transaction submitted successfully!");
            console.log("Transaction hash:", committedTransaction.hash);

            // Wait for transaction confirmation
            const executedTransaction = await this.aptos.waitForTransaction({
                transactionHash: committedTransaction.hash,
            });

            // Extract order address from emitted events
            const orderAddress = this.extractOrderAddress(executedTransaction);

            console.log("Order created successfully!");
            console.log("Transaction hash:", executedTransaction.hash);
            console.log("Order address:", orderAddress);

            return {
                transactionHash: executedTransaction.hash,
                orderAddress: orderAddress,
            };
        } catch (error) {
            console.error("Error creating order:", error);
            throw error;
        }
    }

    async createEscrowDst(params: {
        order_hash: Uint8Array;
        incentive_feeAssetMetadata: string;
        depositAssetMetadata: string;
        deposit_amount: number;
        incentive_fee: number;
        hashlock: Uint8Array;
        withDrawPeriod: number;
        publicWithDrawPeriod: number;
        cancelPeriod: number;
        publicCancelPeriod: number;
    }): Promise<{ transactionHash: string; escrowAddress: string }> {
        try {
            console.log("Creating escrow dst transaction...");
            console.log(
                "User account:",
                this.userAccount.accountAddress.toString()
            );
            console.log(
                "Relay account:",
                this.relayAccount.accountAddress.toString()
            );

            // Build the transaction payload
            const payload: InputEntryFunctionData = {
                function: `${this.moduleAddress}::order_factory::create_escrow_dst`,
                typeArguments: [
                    "0x1::fungible_asset::Metadata", // M type for incentive fee asset
                    "0x1::fungible_asset::Metadata", // N type for deposit asset
                ],
                functionArguments: [
                    Array.from(params.order_hash),
                    this.userAccount.accountAddress,
                    params.incentive_feeAssetMetadata,
                    params.depositAssetMetadata,
                    params.deposit_amount,
                    params.incentive_fee,
                    Array.from(this.generateSalt()),
                    Array.from(params.hashlock),
                    params.withDrawPeriod,
                    params.publicWithDrawPeriod,
                    params.cancelPeriod,
                    params.publicCancelPeriod,
                ],
            };

            // functionArguments: [
            //         params.depositAssetMetadata,
            //         params.incentive_feeAssetMetadata,
            //         params.recover_incentive_fee,
            //         params.recoverPeriod,
            //         params.deposit_amount,
            //         params.min_incentive_fee,
            //         Array.from(this.generateSalt()), // Generate salt if not provided
            //         Array.from(params.hashlock),
            //         params.allow_multi_fill,
            //         params.whitelisted_addresses,
            //         params.withDrawPeriod,
            //         params.publicWithDrawPeriod,
            //         params.cancelPeriod,
            //         params.publicCancelPeriod,
            //     ],
            // Build the multi-agent transaction
            const transaction = await this.aptos.transaction.build.simple({
                sender: this.relayAccount.accountAddress,
                data: payload,
            });

            // Sign the transaction with both accounts
            const relayAuthenticator = this.aptos.transaction.sign({
                signer: this.relayAccount,
                transaction,
            });

            // Submit the multi-agent transaction
            const committedTransaction =
                await this.aptos.transaction.submit.simple({
                    transaction,
                    senderAuthenticator: relayAuthenticator,
                });

            console.log("Transaction submitted successfully!");
            console.log("Transaction hash:", committedTransaction.hash);

            // Wait for transaction confirmation
            const executedTransaction = await this.aptos.waitForTransaction({
                transactionHash: committedTransaction.hash,
            });

            // Extract escrow address from emitted events
            const escrowAddress =
                this.extractDSTEscrowAddress(executedTransaction);

            console.log("Escrow dst created successfully!");
            console.log("Transaction hash:", executedTransaction.hash);
            console.log("Escrow address:", escrowAddress);

            return {
                transactionHash: executedTransaction.hash,
                escrowAddress: escrowAddress,
            };
        } catch (error) {
            console.error("Error creating escrow dst:", error);
            throw error;
        }
    }

    private extractDSTEscrowAddress(transaction: any): string {
        try {
            // Look for the EscrowCreatedEvent in the transaction events
            const escrowCreatedEvent = transaction.events?.find((event: any) =>
                event.type.includes("EscrowDstCreatedEvent")
            );

            if (!escrowCreatedEvent) {
                throw new Error(
                    "EscrowCreatedEvent not found in transaction events"
                );
            }

            // Extract the escrow_address from the event data
            const escrowAddress = escrowCreatedEvent.data.escrow_address;

            if (!escrowAddress) {
                throw new Error("escrow_address not found in event data");
            }

            return escrowAddress;
        } catch (error) {
            console.error("Error extracting escrow address:", error);
            throw new Error(`Failed to extract escrow address: ${error}`);
        }
    }

    private extractOrderAddress(transaction: any): string {
        try {
            // Look for the OrderCreatedEvent in the transaction events
            const orderCreatedEvent = transaction.events?.find((event: any) =>
                event.type.includes("OrderCreatedEvent")
            );

            if (!orderCreatedEvent) {
                throw new Error(
                    "OrderCreatedEvent not found in transaction events"
                );
            }

            // Extract the order_address from the event data
            const orderAddress = orderCreatedEvent.data.order_address;

            if (!orderAddress) {
                throw new Error("order_address not found in event data");
            }

            return orderAddress;
        } catch (error) {
            console.error("Error extracting order address:", error);
            throw new Error(`Failed to extract order address: ${error}`);
        }
    }

    async createEscrow(params: {
        orderAddress: string;
        depositAssetMetadata: string;
        incentive_feeAssetMetadata: string;
        makeAmount: number;
        incentiveFee: number;
        receiver: string;
        salt?: Uint8Array;
    }): Promise<{ transactionHash: string; escrowAddress: string }> {
        try {
            console.log("Creating escrow transaction...");
            console.log(
                "Relay account (sender):",
                this.relayAccount.accountAddress.toString()
            );
            console.log("Order address:", params.orderAddress);

            // Generate salt if not provided
            const salt = params.salt || this.generateSalt();

            const payload: InputEntryFunctionData = {
                function: `${this.moduleAddress}::order_factory::create_escrow_src`,
                typeArguments: [
                    "0x1::fungible_asset::Metadata", // M: incentive fee asset metadata
                    "0x1::fungible_asset::Metadata", // N: deposit asset metadata
                ],
                functionArguments: [
                    params.orderAddress,
                    params.incentive_feeAssetMetadata,
                    params.depositAssetMetadata,
                    params.makeAmount,
                    params.incentiveFee,
                    params.receiver,
                    Array.from(salt),
                ],
            };

            // Build the transaction (relay is the only signer for this function)
            const transaction = await this.aptos.transaction.build.simple({
                sender: this.relayAccount.accountAddress,
                data: payload,
            });

            // Sign the transaction with relay account
            const senderAuthenticator = this.aptos.transaction.sign({
                signer: this.relayAccount,
                transaction,
            });

            // Submit the transaction
            const committedTransaction =
                await this.aptos.transaction.submit.simple({
                    transaction,
                    senderAuthenticator,
                });

            console.log("Transaction submitted:", committedTransaction.hash);

            // Wait for transaction confirmation
            const executedTransaction = await this.aptos.waitForTransaction({
                transactionHash: committedTransaction.hash,
            });

            // Extract escrow address from emitted events
            const escrowAddress =
                this.extractEscrowAddress(executedTransaction);

            console.log("Escrow created successfully!");
            console.log("Transaction hash:", executedTransaction.hash);
            console.log("Escrow address:", escrowAddress);

            return {
                transactionHash: executedTransaction.hash,
                escrowAddress: escrowAddress,
            };
        } catch (error) {
            console.error("Error creating escrow:", error);
            throw error;
        }
    }

    private extractEscrowAddress(transaction: any): string {
        try {
            // Look for the EscrowCreatedEvent in the transaction events
            const escrowCreatedEvent = transaction.events?.find((event: any) =>
                event.type.includes("EscrowCreatedEvent")
            );

            if (!escrowCreatedEvent) {
                throw new Error(
                    "EscrowCreatedEvent not found in transaction events"
                );
            }

            // Extract the escrow_address from the event data
            const escrowAddress = escrowCreatedEvent.data.escrow_address;

            if (!escrowAddress) {
                throw new Error("escrow_address not found in event data");
            }

            return escrowAddress;
        } catch (error) {
            console.error("Error extracting escrow address:", error);
            throw new Error(`Failed to extract escrow address: ${error}`);
        }
    }

    async withdrawAssets(params: {
        escrowAddress: string;
        secret: Uint8Array;
        incentive_feeAssetMetadata: string;
        depositAssetMetadata: string;
        receiverAccount?: Account; // Optional, defaults to userAccount
    }): Promise<{ transactionHash: string }> {
        try {
            console.log("Withdrawing assets from escrow...");

            // Use provided receiver account or default to user account
            const receiverAccount = params.receiverAccount || this.relayAccount;
            console.log(
                "Receiver account:",
                receiverAccount.accountAddress.toString()
            );
            console.log("Escrow address:", params.escrowAddress);

            // Convert secret to bytes for the keccak hash verification
            // const secretBytes = new TextEncoder().encode(params.secret);

            const payload: InputEntryFunctionData = {
                function: `${this.moduleAddress}::order_factory::withdraw`,
                typeArguments: [
                    "0x1::fungible_asset::Metadata", // M: incentive fee asset metadata
                    "0x1::fungible_asset::Metadata", // N: deposit asset metadata
                ],
                functionArguments: [
                    params.escrowAddress,
                    Array.from(params.secret), // Convert Uint8Array to Array for serialization
                    params.incentive_feeAssetMetadata,
                    params.depositAssetMetadata,
                ],
            };

            // Build the transaction (receiver is the signer)
            const transaction = await this.aptos.transaction.build.simple({
                sender: receiverAccount.accountAddress,
                data: payload,
            });

            // Sign the transaction with receiver account
            const senderAuthenticator = this.aptos.transaction.sign({
                signer: receiverAccount,
                transaction,
            });

            // Submit the transaction
            const committedTransaction =
                await this.aptos.transaction.submit.simple({
                    transaction,
                    senderAuthenticator,
                });

            console.log("Transaction submitted:", committedTransaction.hash);

            // Wait for transaction confirmation
            const executedTransaction = await this.aptos.waitForTransaction({
                transactionHash: committedTransaction.hash,
            });
            console.log("Assets withdrawn successfully!");
            console.log("Transaction hash:", executedTransaction.hash);

            return {
                transactionHash: executedTransaction.hash,
            };
        } catch (error) {
            console.error("Error withdrawing assets:", error);
            throw error;
        }
    }

    async checkAccountBalances() {
        try {
            const userBalance = await this.aptos.getAccountAPTAmount({
                accountAddress: this.userAccount.accountAddress,
            });

            const relayBalance = await this.aptos.getAccountAPTAmount({
                accountAddress: this.relayAccount.accountAddress,
            });

            console.log(`User account balance: ${userBalance} APT`);
            console.log(`Relay account balance: ${relayBalance} APT`);
        } catch (error) {
            console.error("Error checking balances:", error);
        }
    }
}

class ResolverManager {
    public provider: Provider;
    public transactionSigner: Wallet; // Signs the resolver contract transaction
    private resolver: Contract;
    public addresses: {
        resolver: string;
        lop: string;
        factory: string;
        token: string;
        takerToken: string;
    };

    constructor(transactionSignerPrivateKey: string) {
        // Initialize provider and transaction signer
        this.provider = new ethers.JsonRpcProvider(process.env.RPC_URL!);
        this.transactionSigner = new ethers.Wallet(
            transactionSignerPrivateKey,
            this.provider
        );

        // Contract addresses
        this.addresses = {
            resolver: process.env.RESOLVER_ADDRESS!,
            lop: process.env.LOP_ADDRESS!,
            factory: process.env.FACTORY_ADDRESS!,
            token: process.env.TOKEN_ADDRESS!,
            takerToken: process.env.TAKER_TOKEN_ADDRESS!,
        };

        // Initialize resolver contract with transaction signer
        this.resolver = new ethers.Contract(
            this.addresses.resolver,[
        {
            "type": "constructor",
            "inputs": [
                { "name": "lop", "type": "address", "internalType": "address" },
                {
                    "name": "factory",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "initialOwner",
                    "type": "address",
                    "internalType": "address"
                }
            ],
            "stateMutability": "nonpayable"
        },
        { "type": "receive", "stateMutability": "payable" },
        {
            "type": "function",
            "name": "deployDst",
            "inputs": [
                {
                    "name": "orderHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "hashlock",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "maker",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "amount",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "timelocks",
                    "type": "uint256",
                    "internalType": "Timelocks"
                }
            ],
            "outputs": [],
            "stateMutability": "payable"
        },
        {
            "type": "function",
            "name": "deploySrc",
            "inputs": [
                {
                    "name": "order",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                },
                { "name": "v", "type": "uint8", "internalType": "uint8" },
                { "name": "r", "type": "bytes32", "internalType": "bytes32" },
                { "name": "s", "type": "bytes32", "internalType": "bytes32" },
                {
                    "name": "immutables",
                    "type": "tuple",
                    "internalType": "struct IBaseEscrow.Immutables",
                    "components": [
                        {
                            "name": "orderHash",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "hashlock",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "taker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "token",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "amount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "safetyDeposit",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "timelocks",
                            "type": "uint256",
                            "internalType": "Timelocks"
                        }
                    ]
                },
                {
                    "name": "amount",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                { "name": "permit", "type": "bytes", "internalType": "bytes" },
                {
                    "name": "extraDataArgs",
                    "type": "tuple",
                    "internalType": "struct IEscrowFactory.ExtraDataArgs",
                    "components": [
                        {
                            "name": "hashlockInfo",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "dstChainId",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "dstToken",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "deposits",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "timelocks",
                            "type": "uint256",
                            "internalType": "Timelocks"
                        }
                    ]
                }
            ],
            "outputs": [
                { "name": "", "type": "address", "internalType": "address" }
            ],
            "stateMutability": "payable"
        },
        {
            "type": "function",
            "name": "getDefaultTimelock",
            "inputs": [
                {
                    "name": "srcWithdrawalDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "srcPublicWithdrawalDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "srcCancellationDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "srcPublicCancellationDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "dstWithdrawalDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "dstPublicWithdrawalDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                },
                {
                    "name": "dstCancellationDelay",
                    "type": "uint32",
                    "internalType": "uint32"
                }
            ],
            "outputs": [
                { "name": "", "type": "uint256", "internalType": "Timelocks" }
            ],
            "stateMutability": "pure"
        },
        {
            "type": "function",
            "name": "getDstAddress",
            "inputs": [
                {
                    "name": "orderHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                }
            ],
            "outputs": [
                { "name": "", "type": "address", "internalType": "address" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getEscrowAddress",
            "inputs": [
                {
                    "name": "orderHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                }
            ],
            "outputs": [
                { "name": "", "type": "address", "internalType": "address" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getExtensions",
            "inputs": [
                {
                    "name": "extraDataArgs",
                    "type": "tuple",
                    "internalType": "struct IEscrowFactory.ExtraDataArgs",
                    "components": [
                        {
                            "name": "hashlockInfo",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "dstChainId",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "dstToken",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "deposits",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "timelocks",
                            "type": "uint256",
                            "internalType": "Timelocks"
                        }
                    ]
                },
                { "name": "permit", "type": "bytes", "internalType": "bytes" }
            ],
            "outputs": [
                { "name": "", "type": "bytes", "internalType": "bytes" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getExtensionsHash",
            "inputs": [
                {
                    "name": "extensions",
                    "type": "bytes",
                    "internalType": "bytes"
                }
            ],
            "outputs": [
                { "name": "", "type": "bytes32", "internalType": "bytes32" }
            ],
            "stateMutability": "pure"
        },
        {
            "type": "function",
            "name": "getExtraDataArgs",
            "inputs": [
                {
                    "name": "hashlockInfo",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "timelocks",
                    "type": "uint256",
                    "internalType": "Timelocks"
                }
            ],
            "outputs": [
                {
                    "name": "",
                    "type": "tuple",
                    "internalType": "struct IEscrowFactory.ExtraDataArgs",
                    "components": [
                        {
                            "name": "hashlockInfo",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "dstChainId",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "dstToken",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "deposits",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "timelocks",
                            "type": "uint256",
                            "internalType": "Timelocks"
                        }
                    ]
                }
            ],
            "stateMutability": "pure"
        },
        {
            "type": "function",
            "name": "getImmutables",
            "inputs": [
                {
                    "name": "orderHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "hashlock",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "maker",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "amount",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "timelocks",
                    "type": "uint256",
                    "internalType": "Timelocks"
                }
            ],
            "outputs": [
                {
                    "name": "",
                    "type": "tuple",
                    "internalType": "struct IBaseEscrow.Immutables",
                    "components": [
                        {
                            "name": "orderHash",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "hashlock",
                            "type": "bytes32",
                            "internalType": "bytes32"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "taker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "token",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "amount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "safetyDeposit",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "timelocks",
                            "type": "uint256",
                            "internalType": "Timelocks"
                        }
                    ]
                }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getOrder",
            "inputs": [
                {
                    "name": "extensionsHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "maker",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "mockTakerToken",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "makeAmount",
                    "type": "uint256",
                    "internalType": "uint256"
                }
            ],
            "outputs": [
                {
                    "name": "",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getOrderAndHash",
            "inputs": [
                {
                    "name": "extensionsHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "maker",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "mockTakerToken",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "makeAmount",
                    "type": "uint256",
                    "internalType": "uint256"
                }
            ],
            "outputs": [
                {
                    "name": "",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                },
                { "name": "", "type": "bytes32", "internalType": "bytes32" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getOrderHash",
            "inputs": [
                {
                    "name": "order",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                }
            ],
            "outputs": [
                { "name": "", "type": "bytes32", "internalType": "bytes32" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getOrderHashLocal",
            "inputs": [
                {
                    "name": "order",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                }
            ],
            "outputs": [
                { "name": "", "type": "bytes32", "internalType": "bytes32" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getPermitDigest",
            "inputs": [
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "owner",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "spender",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "value",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "deadline",
                    "type": "uint256",
                    "internalType": "uint256"
                }
            ],
            "outputs": [
                { "name": "", "type": "bytes32", "internalType": "bytes32" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "getTakingAmount",
            "inputs": [
                {
                    "name": "order",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                },
                {
                    "name": "extension",
                    "type": "bytes",
                    "internalType": "bytes"
                },
                {
                    "name": "orderHash",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "taker",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "makingAmount",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "remainingMakingAmount",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "extraData",
                    "type": "bytes",
                    "internalType": "bytes"
                }
            ],
            "outputs": [
                { "name": "", "type": "uint256", "internalType": "uint256" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "isValidOrderSig",
            "inputs": [
                {
                    "name": "order",
                    "type": "tuple",
                    "internalType": "struct IOrderMixin.Order",
                    "components": [
                        {
                            "name": "salt",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "maker",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "receiver",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "takerAsset",
                            "type": "uint256",
                            "internalType": "Address"
                        },
                        {
                            "name": "makingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "takingAmount",
                            "type": "uint256",
                            "internalType": "uint256"
                        },
                        {
                            "name": "makerTraits",
                            "type": "uint256",
                            "internalType": "MakerTraits"
                        }
                    ]
                },
                { "name": "v", "type": "uint8", "internalType": "uint8" },
                { "name": "r", "type": "bytes32", "internalType": "bytes32" },
                { "name": "s", "type": "bytes32", "internalType": "bytes32" },
                {
                    "name": "signer",
                    "type": "address",
                    "internalType": "address"
                }
            ],
            "outputs": [{ "name": "", "type": "bool", "internalType": "bool" }],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "owner",
            "inputs": [],
            "outputs": [
                { "name": "", "type": "address", "internalType": "address" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "packSig",
            "inputs": [
                { "name": "v", "type": "uint8", "internalType": "uint8" },
                { "name": "r", "type": "bytes32", "internalType": "bytes32" },
                { "name": "s", "type": "bytes32", "internalType": "bytes32" },
                {
                    "name": "token",
                    "type": "address",
                    "internalType": "address"
                },
                {
                    "name": "value",
                    "type": "uint256",
                    "internalType": "uint256"
                },
                {
                    "name": "deadline",
                    "type": "uint256",
                    "internalType": "uint256"
                }
            ],
            "outputs": [
                { "name": "", "type": "bytes", "internalType": "bytes" }
            ],
            "stateMutability": "view"
        },
        {
            "type": "function",
            "name": "renounceOwnership",
            "inputs": [],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "transferOwnership",
            "inputs": [
                {
                    "name": "newOwner",
                    "type": "address",
                    "internalType": "address"
                }
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "function",
            "name": "withdraw",
            "inputs": [
                {
                    "name": "secret",
                    "type": "bytes32",
                    "internalType": "bytes32"
                },
                {
                    "name": "escrow",
                    "type": "address",
                    "internalType": "address"
                }
            ],
            "outputs": [],
            "stateMutability": "nonpayable"
        },
        {
            "type": "event",
            "name": "EscrowCreated",
            "inputs": [
                {
                    "name": "escrow",
                    "type": "address",
                    "indexed": false,
                    "internalType": "address"
                }
            ],
            "anonymous": false
        },
        {
            "type": "event",
            "name": "OwnershipTransferred",
            "inputs": [
                {
                    "name": "previousOwner",
                    "type": "address",
                    "indexed": true,
                    "internalType": "address"
                },
                {
                    "name": "newOwner",
                    "type": "address",
                    "indexed": true,
                    "internalType": "address"
                }
            ],
            "anonymous": false
        },
        {
            "type": "error",
            "name": "OwnableInvalidOwner",
            "inputs": [
                {
                    "name": "owner",
                    "type": "address",
                    "internalType": "address"
                }
            ]
        },
        {
            "type": "error",
            "name": "OwnableUnauthorizedAccount",
            "inputs": [
                {
                    "name": "account",
                    "type": "address",
                    "internalType": "address"
                }
            ]
        }
    ],
            this.transactionSigner // Transaction signer calls the resolver
        );
    }

    private async createPermitSignature(
        tokenAddress: string,
        owner: string,
        spender: string,
        value: bigint,
        deadline: bigint,
        ownerPrivateKey: string
    ): Promise<string> {
        value = BigInt(10000000000000000000000); // Ensure value is a bigint
        // Get the permit digest from the contract
        const permitDigest = await this.resolver.getPermitDigest(
            tokenAddress,
            owner,
            spender,
            value,
            deadline
        );
        console.log("Owner");
        console.log("👤 Owner address:", owner);
        console.log("👤 Spender address:", spender);
        console.log("Token address:", tokenAddress);
        const tokenABI = [
            "function balanceOf(address owner) view returns (uint256)",
        ];
        const tokenContract = new ethers.Contract(
            tokenAddress,
            tokenABI,
            this.provider
        );
        const balance = await tokenContract.balanceOf(owner);
        console.log("👤 Owner balance:", ethers.formatEther(balance), "ETH");

        console.log("🔍 Permit digest:", permitDigest);

        // Create SigningKey and sign the RAW hash (no prefix)
        const signingKey = new SigningKey(ownerPrivateKey);
        const { v, r, s } = signingKey.sign(permitDigest); // ✅ Signs raw hash

        // Convert to compact format

        // const sig = ethers.Signature.from(signature);
        const compactSig = await this.resolver.packSig(
            v,
            r,
            s,
            tokenAddress,
            value,
            deadline
        );

        console.log("✍️ Permit signature:", compactSig);
        return compactSig;
    }

    // ✅ CORRECTED: Sign raw order hash and return v, r, s using SigningKey
    private async createOrderSignature(
        orderHash: string,
        makerPrivateKey: string
    ): Promise<{ v: number; r: string; s: string }> {
        console.log("🔍 Order hash:", orderHash);

        // Create SigningKey and sign the RAW hash (no prefix)
        const signingKey = new SigningKey(makerPrivateKey);
        const signature = signingKey.sign(orderHash); // ✅ Signs raw hash

        console.log("✍️ Order signature object:", signature);

        // ✅ Return in the format expected by Solidity
        return {
            v: signature.v, // Recovery ID (27 or 28)
            r: signature.r, // First 32 bytes of signature
            s: signature.s, // Second 32 bytes of signature
        };
    }

    async deployDst(params: {
        orderHash: Uint8Array;
        secret: Uint8Array;
        amount: bigint;
        makerAddress: string,
        timeDelays?: {
            srcWithdrawalDelay: number;
            srcPublicWithdrawalDelay: number;
            srcCancellationDelay: number;
            srcPublicCancellationDelay: number;
            dstWithdrawalDelay: number;
            dstPublicWithdrawalDelay: number;
            dstCancellationDelay: number;
        };
    }): Promise<{ escrowAddress: string; transactionHash: string }> {
        const hashlock = ethers.keccak256(params.secret);
        console.log("🔒 Hashlock generated:", hashlock);
        const delays = params.timeDelays || {
            srcWithdrawalDelay: 10,
            srcPublicWithdrawalDelay: 10 * 60,
            srcCancellationDelay: 15 * 60,
            srcPublicCancellationDelay: 20 * 60,
            dstWithdrawalDelay: 10,
            dstPublicWithdrawalDelay: 10 * 60,
            dstCancellationDelay: 15 * 60,
        };

        const timelocks = await this.resolver.getDefaultTimelock(
            delays.srcWithdrawalDelay,
            delays.srcPublicWithdrawalDelay,
            delays.srcCancellationDelay,
            delays.srcPublicCancellationDelay,
            delays.dstWithdrawalDelay,
            delays.dstPublicWithdrawalDelay,
            delays.dstCancellationDelay
        );

        const tx = await this.resolver.deployDst(
            params.orderHash,
            hashlock, // The hashlock generated from the secret
            this.addresses.token,
            params.makerAddress,
            params.amount,
            timelocks,
            {
                // value: params.safetyDeposit || 0n,
                gasLimit: 5000000n, // ✅ Set high manual gas limit (5M gas)
                gasPrice: ethers.parseUnits("20", "gwei"), // ✅ Set manual gas price
            }
        );
        const receipt = await tx.wait();

        const escrowAddress: string = await this.resolver.getDstAddress(
            params.orderHash
        );

        console.log("✅ Dst escrow deployed at:", escrowAddress);

        // Sleep for wait time plus a second
        // Wait for 6 seconds to ensure the contract is deployed
        await new Promise((resolve) =>
            setTimeout(resolve, delays.srcWithdrawalDelay * 1000 + 1000)
        );
        // Call withdraw

        await this.resolver.withdraw(
            params.secret, // The secret used to create the hashlock
            escrowAddress, // The escrow address returned from deploySrc
            {
                // value: params.safetyDeposit || 0n,
                gasLimit: 5000000n, // ✅ Set high manual gas limit (5M gas)
                gasPrice: ethers.parseUnits("20", "gwei"), // ✅ Set manual gas price
            }
        );

        return {
            escrowAddress,
            transactionHash: receipt.transactionHash,
        };
    }

    async deploySrc(params: {
        secret: Uint8Array;
        makerAddress: string;
        makerPrivateKey: string; // Maker signs the order and permit
        makeAmount: bigint;
        safetyDeposit?: bigint;
        timeDelays?: {
            srcWithdrawalDelay: number;
            srcPublicWithdrawalDelay: number;
            srcCancellationDelay: number;
            srcPublicCancellationDelay: number;
            dstWithdrawalDelay: number;
            dstPublicWithdrawalDelay: number;
            dstCancellationDelay: number;
        };
    }): Promise<{ escrowAddress: string; transactionHash: string }> {
        try {
            console.log("🚀 Starting deploySrc process...");
            console.log(
                "📝 Transaction signer:",
                this.transactionSigner.address
            );
            console.log("👤 Order maker:", params.makerAddress);
            const secret = ethers.keccak256(params.secret);
            // Step 1: Generate hashlock from secret
            const hashlock = ethers.keccak256(secret);
            console.log("🔒 Hashlock generated:", hashlock);

            // Step 2: Get default timelock
            const delays = params.timeDelays || {
                srcWithdrawalDelay: 10,
                srcPublicWithdrawalDelay: 10 * 60,
                srcCancellationDelay: 15 * 60,
                srcPublicCancellationDelay: 20 * 60,
                dstWithdrawalDelay: 10,
                dstPublicWithdrawalDelay: 10 * 60,
                dstCancellationDelay: 15 * 60,
            };

            const timelocks = await this.resolver.getDefaultTimelock(
                delays.srcWithdrawalDelay,
                delays.srcPublicWithdrawalDelay,
                delays.srcCancellationDelay,
                delays.srcPublicCancellationDelay,
                delays.dstWithdrawalDelay,
                delays.dstPublicWithdrawalDelay,
                delays.dstCancellationDelay
            );

            console.log("⏳ Timelocks", timelocks);

            const extraDataArgs = await this.resolver.getExtraDataArgs(
                hashlock,
                timelocks
            );

            console.log("ExtraDataArgs:", extraDataArgs);

            const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);
            console.log("📝 Creating permit signature...");
            console.log("   Owner (maker):", params.makerAddress);
            console.log("   Spender (LOP):", this.addresses.lop);

            // Check the balance of the maker address is high enough using erc20

            const permit = await this.createPermitSignature(
                this.addresses.token,
                params.makerAddress, // Owner = maker
                this.addresses.lop, // Spender = LOP contract
                params.makeAmount,
                deadline,
                params.makerPrivateKey // Maker signs the permit
            );

            // Step 5: Get extensions
            const extensionsT = await this.resolver.getExtensions(
                [...extraDataArgs],
                permit
            );
            const extensions = extensionsT;

            console.log("Extensions data:", extensionsT);

            // Step 6: Get extensions hash and create order
            const extensionsHash = ethers.keccak256(extensions);

            console.log("Extensions hash:", extensionsHash);

            const order = await this.resolver.getOrder(
                extensionsHash,
                params.makerAddress,
                this.addresses.token,
                this.addresses.takerToken,
                params.makeAmount
            );
            console.log("Order data:", order);
            const orderHash = await this.resolver.getOrderHash([...order]);

            console.log("Order", order);
            console.log("🔍 Order hash:", orderHash);
            console.log("📝 Creating order signature...");
            console.log("   Order signer (maker):", params.makerAddress);

            const { v, r, s } = await this.createOrderSignature(
                orderHash,
                params.makerPrivateKey // Maker signs the order
            );

            console.log("Order signature:", { v, r, s });
            const isValidSig = await this.resolver.isValidOrderSig(
                [...order],
                v,
                r,
                s,
                params.makerAddress // Maker address
            );
            console.log("✅ Order signature valid:", isValidSig);

            // Step 8: Get immutables
            const immutablesData = await this.resolver.getImmutables(
                orderHash,
                hashlock,
                params.makerAddress,
                this.addresses.token,
                params.makeAmount,
                timelocks
            );
            const immutables = immutablesData;
            console.log("Immutables data:", immutables);

            // Step 9: Call deploySrc (transaction signer calls the resolver)
            console.log("📝 Calling deploySrc with transaction signer...");
            console.log(
                "   Transaction will be sent by:",
                this.transactionSigner.address
            );

            console.log("   Immutables:", immutables);
            console.log("   Order:", order);
            console.log("   Permit:", permit);
            console.log("   Extensions:", extensions);
            console.log("   ExtraDataArgs:", extraDataArgs);
            console.log("   v:", v, "r:", r, "s:", s);
            console.log(" makeAmount:", params.makeAmount);
            console.log("maker private key ", params.makerPrivateKey);

            const val = await this.resolver.isValidOrderSig(
                [...order],
                v,
                r,
                s,
                params.makerAddress // Maker address
            );
            console.log("✅ Order signature valid:", val);
            const hash = await this.resolver.getOrderHash([...order]);
            console.log("Order hash:", hash);

            // ✅ Deploy the source contract with all parameters
            console.log("⏳ Deploying source contract...");
            const tx = await this.resolver.deploySrc(
                [...order],
                v,
                r,
                s,
                [...immutables],
                params.makeAmount,
                permit,
                [...extraDataArgs],
                {
                    // value: params.safetyDeposit || 0n,
                    gasLimit: 5000000n, // ✅ Set high manual gas limit (5M gas)
                    gasPrice: ethers.parseUnits("20", "gwei"), // ✅ Set manual gas price
                }
            );

            console.log("⏳ Transaction submitted:", tx.hash);
            const receipt = await tx.wait();
            console.log("✅ Transaction confirmed!", receipt);

            const escrowAddress: string = await this.resolver.getEscrowAddress(
                orderHash
            );
            console.log("Escrow address:", escrowAddress);
            // Wait for 6 seconds to ensure the contract is deployed
            await new Promise((resolve) =>
                setTimeout(resolve, delays.srcWithdrawalDelay * 1000 + 1000)
            );
            // Call withdraw

            await this.resolver.withdraw(
                secret, // The secret used to create the hashlock
                escrowAddress, // The escrow address returned from deploySrc
                {
                    // value: params.safetyDeposit || 0n,
                    gasLimit: 5000000n, // ✅ Set high manual gas limit (5M gas)
                    gasPrice: ethers.parseUnits("20", "gwei"), // ✅ Set manual gas price
                }
            );

            return {
                escrowAddress,
                transactionHash: tx.hash,
            };
        } catch (error) {
            console.error("❌ Error in deploySrc:", error);
            throw error;
        }
    }

    async checkBalance(address: string): Promise<string> {
        const balance = await this.provider.getBalance(address);
        return ethers.formatEther(balance);
    }
}

function hashSecretWithEthers(secret: Uint8Array): Uint8Array {
    const hash = keccak256(secret);
    // Remove '0x' prefix and convert to Uint8Array
    const hashBytes = hash.slice(2);
    return new Uint8Array(Buffer.from(hashBytes, "hex"));
}

// Example usage
async function main() {
    try {
        // =======================================================
        // ======================= APT SRC =======================
        // =======================================================

        // const orderManager = new AptosOrderManager();

        // // // Check account balances first
        // await orderManager.checkAccountBalances();

        // // Random secret bytes of length 32
        // const secret = new Uint8Array(32);
        // crypto.getRandomValues(secret);
        // // Hash the secret using keccak256
        // const hashlock = hashSecretWithEthers(secret);
        // const withdrawPeriod = 1; // 6 seconds for testing
        // // Example order parameters
        // const orderParams = {
        //     depositAssetMetadata:
        //         "0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d", // Replace with actual metadata object
        //     incentive_feeAssetMetadata:
        //         "0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e", // Replace with actual metadata object
        //     recover_incentive_fee: 10, // 0.01 APT (in octas)
        //     recoverPeriod: 86400, // 24 hours in seconds
        //     deposit_amount: 100, // 1 APT (in octas)
        //     min_incentive_fee: 10, // 0.001 APT (in octas)
        //     // salt: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]), // 8-byte salt
        //     hashlock:  hashlock, //
        //     allow_multi_fill: true,
        //     whitelisted_addresses: [
        //         // Relay address
        //         process.env.RELAY_ACCOUNT_ADDRESS!,
        //         // Add more addresses if needed
        //     ],
        //     withDrawPeriod: withdrawPeriod, // 1 hour
        //     publicWithDrawPeriod: 7200, // 2 hours
        //     cancelPeriod: 1800, // 30 minutes
        //     publicCancelPeriod: 3600, // 1 hour
        // };

        // const orderResult = await orderManager.createOrder(orderParams);
        // console.log("Order created:", orderResult.orderAddress);

        // // Step 2: Create an escrow for the order
        // console.log("\n=== Creating Escrow ===");
        // const escrowParams = {
        //     orderAddress: orderResult.orderAddress,
        //     depositAssetMetadata:
        //         "0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d", // Replace with actual metadata object
        //     incentive_feeAssetMetadata:
        //         "0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e", // Replace with actual metadata object
        //     makeAmount: 50, // 0.5 tokens (half of the order amount)
        //     incentiveFee: 20, // 0.002 tokens
        //     receiver:
        //         "0x3926348fbe4db32987c5ff2306d67efe3450bd9c5fc58745f7852f9ef4dc13f1", // User address
        // };

        // const escrowResult = await orderManager.createEscrow(escrowParams);
        // console.log("Escrow created:", escrowResult.escrowAddress);

        // console.log("\n=== Summary ===");
        // console.log("Order Address:", orderResult.orderAddress);
        // console.log("Order Transaction:", orderResult.transactionHash);
        // console.log("Escrow Address:", escrowResult.escrowAddress);
        // console.log("Escrow Transaction:", escrowResult.transactionHash);

        // //  Wait for 6 seconds before withdrawing assets
        // console.log("\n=== Withdrawing Assets ===");
        // await new Promise((resolve) => setTimeout(resolve, withdrawPeriod * 1000 + 1000));
        // const withdrawParams = {
        //     escrowAddress: escrowResult.escrowAddress,
        //     secret: secret, // The same secret used to create the order hashlock
        //     incentive_feeAssetMetadata: orderParams.incentive_feeAssetMetadata,
        //     depositAssetMetadata: orderParams.depositAssetMetadata,
        // };

        // const withdrawResult = await orderManager.withdrawAssets(
        //     withdrawParams
        // );
        // console.log("Assets withdrawn successfully!");

        // =======================================================
        // ======================= APT DST =======================
        // =======================================================

        // const orderManager = new AptosOrderManager();

        // // // Check account balances first
        // await orderManager.checkAccountBalances();

        // // Random secret bytes of length 32
        // const secret = new Uint8Array(32);
        // crypto.getRandomValues(secret);
        // // Hash the secret using keccak256
        // const hashlock = hashSecretWithEthers(secret);
        // const withdrawPeriod = 1; // 6 seconds for testing
        // // Example order parameters
        // const escrowParams = {
        //     order_hash: new Uint8Array(32), // Replace with actual order hash
        //     depositAssetMetadata:
        //         "0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d", // Replace with actual metadata object
        //     incentive_feeAssetMetadata:
        //         "0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e",
        //     deposit_amount: 1000,
        //     incentive_fee: 10,
        //     hashlock: hashlock,
        //     withDrawPeriod: withdrawPeriod,
        //     publicWithDrawPeriod: 7200,
        //     cancelPeriod: 86400,
        //     publicCancelPeriod: 172800,
        // };
        // const escrowResult = await orderManager.createEscrowDst(escrowParams);

        // console.log("Escrow created:", escrowResult.escrowAddress);
        // //  Wait for 6 seconds before withdrawing assets
        // console.log("\n=== Withdrawing Assets ===");
        // await new Promise((resolve) =>
        //     setTimeout(resolve, withdrawPeriod * 1000 + 1000)
        // );
        // const withdrawParams = {
        //     escrowAddress: escrowResult.escrowAddress,
        //     secret: secret, // The same secret used to create the order hashlock
        //     incentive_feeAssetMetadata: escrowParams.incentive_feeAssetMetadata,
        //     depositAssetMetadata: escrowParams.depositAssetMetadata,
        // };

        // const withdrawResult = await orderManager.withdrawAssets(
        //     withdrawParams
        // );
        // console.log("Assets withdrawn successfully!");

        // =======================================================
        // ======================= ETH SRC =======================
        // =======================================================

        // const transactionSignerPrivateKey =
        //     process.env.TRANSACTION_SIGNER_PRIVATE_KEY!; // Calls resolver
        // const makerPrivateKey = process.env.MAKER_PRIVATE_KEY!; // Signs order and permit
        // const makerAddress = process.env.MAKER_ADDRESS!;

        // // Initialize resolver manager with transaction signer
        // const resolverManager = new ResolverManager(
        //     transactionSignerPrivateKey
        // );

        // // Check balances
        // const transactionSignerBalance = await resolverManager.checkBalance(
        //     resolverManager.transactionSigner.address
        // );
        // console.log(
        //     "Transaction Signer Balance:",
        //     transactionSignerBalance,
        //     "ETH"
        // );

        // // Deploy source escrow
        // const deployParams = {
        //     secret: secret,
        //     makerAddress: makerAddress, // Maker's address
        //     makerPrivateKey: makerPrivateKey, // Maker's private key (for signing)
        //     makeAmount: BigInt("1000000000"), // 1 ETH in wei
        //     safetyDeposit: BigInt("0"), // 0.1 ETH in wei
        // };

        // console.log("🚀 Deploying source escrow...");
        // console.log(
        //     "📝 Transaction will be sent by:",
        //     resolverManager.transactionSigner.address
        // );
        // console.log("👤 Order will be signed by:", makerAddress);

        // const result = await resolverManager.deploySrc(deployParams);

        // console.log("✅ Source escrow deployed successfully!");
        // console.log("📍 Escrow Address:", result.escrowAddress);
        // console.log("🔗 Transaction Hash:", result.transactionHash);

        // =======================================================
        // ======================= ETH DST =======================
        // =======================================================

        const secret = new Uint8Array(32);
        crypto.getRandomValues(secret);
        // Hash the secret using keccak256
        const hashlock = hashSecretWithEthers(secret);

        const transactionSignerPrivateKey =
            process.env.TRANSACTION_SIGNER_PRIVATE_KEY!; // Calls resolver
        const makerPrivateKey = process.env.MAKER_PRIVATE_KEY!; // Signs order and permit
        const makerAddress = process.env.MAKER_ADDRESS!;

        // Initialize resolver manager with transaction signer
        const resolverManager = new ResolverManager(
            transactionSignerPrivateKey
        );

        // Check balances
        const transactionSignerBalance = await resolverManager.checkBalance(
            resolverManager.transactionSigner.address
        );
        console.log(
            "Transaction Signer Balance:",
            transactionSignerBalance,
            "ETH"
        );

        // Deploy destination escrow
        const orderHash = new Uint8Array(32);
        crypto.getRandomValues(orderHash);
        const deployParams = {
            orderHash: orderHash, // Use a random order hash for testing
            secret: secret, // The secret used to create the hashlock
            amount: BigInt("1000000"), // 1 ETH in wei
            makerAddress: makerAddress, // Maker's address
            timeDelays: {
                srcWithdrawalDelay: 10,
                srcPublicWithdrawalDelay: 10 * 60,
                srcCancellationDelay: 15 * 60,
                srcPublicCancellationDelay: 20 * 60,
                dstWithdrawalDelay: 10,
                dstPublicWithdrawalDelay: 10 * 60,
                dstCancellationDelay: 15 * 60,
            },
        };
        const { escrowAddress, transactionHash } =
            await resolverManager.deployDst(deployParams);
    } catch (error) {
        console.error("Failed to create order:", error);
        process.exit(1);
    }
}

// Run the script
if (require.main === module) {
    main();
}
