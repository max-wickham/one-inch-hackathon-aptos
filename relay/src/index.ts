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
import { keccak256, toUtf8Bytes } from 'ethers';
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


function hashSecretWithEthers(secret: Uint8Array): Uint8Array {
  const hash = keccak256(secret);
  // Remove '0x' prefix and convert to Uint8Array
  const hashBytes = hash.slice(2);
  return new Uint8Array(Buffer.from(hashBytes, 'hex'));
}


// Example usage
async function main() {
    try {
        const orderManager = new AptosOrderManager();

        // Check account balances first
        await orderManager.checkAccountBalances();

        // Random secret bytes of length 32
        const secret = new Uint8Array(32);
        crypto.getRandomValues(secret);
        // Hash the secret using keccak256
        const hashlock = hashSecretWithEthers(secret);
        const withdrawPeriod = 1; // 6 seconds for testing
        // Example order parameters
        const orderParams = {
            depositAssetMetadata:
                "0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d", // Replace with actual metadata object
            incentive_feeAssetMetadata:
                "0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e", // Replace with actual metadata object
            recover_incentive_fee: 10, // 0.01 APT (in octas)
            recoverPeriod: 86400, // 24 hours in seconds
            deposit_amount: 100, // 1 APT (in octas)
            min_incentive_fee: 10, // 0.001 APT (in octas)
            // salt: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]), // 8-byte salt
            hashlock:  hashlock, // 
            allow_multi_fill: true,
            whitelisted_addresses: [
                // Relay address
                process.env.RELAY_ACCOUNT_ADDRESS!,
                // Add more addresses if needed
            ],
            withDrawPeriod: withdrawPeriod, // 1 hour
            publicWithDrawPeriod: 7200, // 2 hours
            cancelPeriod: 1800, // 30 minutes
            publicCancelPeriod: 3600, // 1 hour
        };

        const orderResult = await orderManager.createOrder(orderParams);
        console.log("Order created:", orderResult.orderAddress);

        // Step 2: Create an escrow for the order
        console.log("\n=== Creating Escrow ===");
        const escrowParams = {
            orderAddress: orderResult.orderAddress,
            depositAssetMetadata:
                "0x1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d", // Replace with actual metadata object
            incentive_feeAssetMetadata:
                "0x8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e", // Replace with actual metadata object
            makeAmount: 50, // 0.5 tokens (half of the order amount)
            incentiveFee: 20, // 0.002 tokens
            receiver:
                "0x3926348fbe4db32987c5ff2306d67efe3450bd9c5fc58745f7852f9ef4dc13f1", // User address
        };

        const escrowResult = await orderManager.createEscrow(escrowParams);
        console.log("Escrow created:", escrowResult.escrowAddress);

        console.log("\n=== Summary ===");
        console.log("Order Address:", orderResult.orderAddress);
        console.log("Order Transaction:", orderResult.transactionHash);
        console.log("Escrow Address:", escrowResult.escrowAddress);
        console.log("Escrow Transaction:", escrowResult.transactionHash);

        //  Wait for 6 seconds before withdrawing assets
        console.log("\n=== Withdrawing Assets ===");
        await new Promise((resolve) => setTimeout(resolve, withdrawPeriod * 1000 + 1000));
        const withdrawParams = {
            escrowAddress: escrowResult.escrowAddress,
            secret: secret, // The same secret used to create the order hashlock
            incentive_feeAssetMetadata: orderParams.incentive_feeAssetMetadata,
            depositAssetMetadata: orderParams.depositAssetMetadata,
        };

        const withdrawResult = await orderManager.withdrawAssets(
            withdrawParams
        );
        console.log("Assets withdrawn successfully!");
    } catch (error) {
        console.error("Failed to create order:", error);
        process.exit(1);
    }
}

// Run the script
if (require.main === module) {
    main();
}
