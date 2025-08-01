import asyncio
import os
from aptos_sdk.account import Account
from aptos_sdk.async_client import FaucetClient, RestClient
from aptos_sdk.transactions import EntryFunction, TransactionPayload, TransactionArgument, RawTransaction
from aptos_sdk.authenticator import Authenticator, MultiEd25519Authenticator
from aptos_sdk.ed25519 import MultiPublicKey, MultiSignature
from aptos_sdk.account_address import AccountAddress
from aptos_sdk.bcs import Serializer
from aptos_sdk.transactions import (
    EntryFunction,
    RawTransaction,
    Script,
    ScriptArgument,
    SignedTransaction,
    TransactionArgument,
    TransactionPayload,
)
import time

# Network configuration
NODE_URL = "http://127.0.0.1:8080/v1"
FAUCET_URL = "http://127.0.0.1:8081/"


relay = Account.load_key(os.environ.get("RELAY_PRIV_KEY"))
user = Account.load_key(os.environ.get("USER_PRIV_KEY"))
# TODO
# FACTORY_ADDRESS
FACTORY = "0xe6727f9d55fa8f220cc4735507b709eaa80b569de07bce38d03c305027554c52::factory::Factory"
INCENTIVE_TOKEN = AccountAddress(bytes.fromhex("1a4589ba938c6613d6f79e88f60cbfa614ee1127255615e1357a1c0e614ae76d"))
DEPOSIT_TOKEN = AccountAddress(bytes.fromhex("8164c59ac168682f0bfcca797ffd6c094ed01aba9ca627a4fab9c8cacbd37c6e"))


async def create_order(rest_client: RestClient, relay: Account, user: Account, hashlock: bytes, salt: bytes):
    # Signed by the relayer and the user
    # Signed by client, sent by relayer
    entry_function = EntryFunction.natural(
        FACTORY,
        "create_order",
        [],
        [
            # TransactionArgument(relay.account_address, Serializer.struct),
            TransactionArgument(user.account_address, Serializer.struct),
            TransactionArgument(DEPOSIT_TOKEN, Serializer.struct),
            TransactionArgument(INCENTIVE_TOKEN, Serializer.struct),
            TransactionArgument(1000, Serializer.u64),  # recover_incentive_fee
            TransactionArgument(7200, Serializer.u64),  # recoverPeriod in seconds
            TransactionArgument(1000, Serializer.u64),  # deposit_amount
            TransactionArgument(100, Serializer.u64),  # min_incentive_fee
            TransactionArgument(salt, Serializer.fixed_bytes),  # salt
            TransactionArgument(hashlock, Serializer.fixed_bytes),  # hashlock
            TransactionArgument(False, Serializer.bool),  # allow_multi_fill
            TransactionArgument([user.account_address], Serializer.sequence_serializer(Serializer.struct)),  # whitelisted_addresses
            TransactionArgument(10, Serializer.u64),  # withDrawPeriod in seconds
            TransactionArgument(1800, Serializer.u64),  # publicWithDrawPeriod in seconds
            TransactionArgument(3600, Serializer.u64),  # cancelPeriod in seconds
            TransactionArgument(100000, Serializer.u64)   # publicCancelPeriod in seconds
        ]
    )
    chain_id = await rest_client.chain_id()
    account_data = await rest_client.account(relay.account_address)
    sequence_number = int(account_data["sequence_number"])

    raw_transaction = RawTransaction(
        sender=relay.account_address,
        sequence_number=sequence_number,
        payload=TransactionPayload(entry_function),
        max_gas_amount=2000,
        gas_unit_price=100,
        expiration_timestamps_secs=(
            int(time.time()) + 10
        ),
        chain_id=chain_id,
    )

    relay_sig = relay.sign(raw_transaction.keyed())
    user_sig = user.sign(raw_transaction.keyed())
    
    multisig_public_key = MultiPublicKey(
        [relay.public_key(), user.public_key()], 2
    )

    multisig_address = AccountAddress.from_key(multisig_public_key)
    
    sig_map = [(0, relay_sig), (1, user_sig)]

    multisig_signature = MultiSignature(sig_map)
    
    authenticator = Authenticator(
        MultiEd25519Authenticator(multisig_public_key, multisig_signature)
    )
    
    signed_transaction = SignedTransaction(raw_transaction, authenticator)
    
    tx_hash = await rest_client.submit_bcs_transaction(signed_transaction)
    await rest_client.wait_for_transaction(tx_hash)
    
    

    
    # Sign transaction with both the relay and user accounts
    
    # Get the emmited order address 

async def create_src(relay: Account, order_address: str ):
    # Deploy the escrow src contract
    # Get the escrow address from the emmited event
    ...
    
async def create_dst():
    ...

async def claim_escrow(escrow_address: str, secret: bytes):
    # Claim the escrow with the secret
    ...


async def main():

    print("relay")
    print(relay.account_address)
    print("user")
    print(user.account_address)
    
    rest_client = RestClient(NODE_URL)
    chain_id = await rest_client.chain_id()
    print(chain_id)
    
    secret = "test".encode('utf-8')
    # TODO calculate hash
    hashlock = bytes.fromhex("9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658")
    # TODO random salt
    salt = b'\x00' * 32  # Example salt, replace with actual
    await create_order(
        rest_client,
        relay=relay,
        user=user,
        hashlock=hashlock,  # Example hashlock, replace with actual
        salt=salt      # Example salt, replace with actual
    )
    
    # Create order
    # Create escrow src
    # Claim escrow

    # # Initialize the clients
    # rest_client = RestClient(NODE_URL)
    # faucet_client = FaucetClient(FAUCET_URL, rest_client)

    # print("Connected to Aptos local node and faucet.")

    # # More code will go here

    # entry_function = EntryFunction.natural(
    #     "0x1::aptos_account",  # Module address and name
    #     "transfer",            # Function name
    #     [],                    # Type arguments (empty for this function)
    #     [
    #         # Function arguments with their serialization type
    #         TransactionArgument(bob.address(), Serializer.struct),  # Recipient address
    #         TransactionArgument(1000, Serializer.u64),              # Amount to transfer (1000 octas)
    #     ],
    # )
    # alice = Account.generate()
    # chain_id = await rest_client.chain_id()
    # account_data = await rest_client.account(alice.address())
    # sequence_number = int(account_data["sequence_number"])

    # raw_transaction = RawTransaction(
    #     sender=alice.address(),                                    # Sender's address
    #     sequence_number=sequence_number,                           # Sequence number to prevent replay attacks
    #     payload=TransactionPayload(entry_function),                # The function to call
    #     max_gas_amount=2000,                                       # Maximum gas units to use
    #     gas_unit_price=100,                                        # Price per gas unit in octas
    #     expiration_timestamps_secs=int(time.time()) + 600,         # Expires in 10 minutes
    #     chain_id=chain_id,                                         # Chain ID to ensure correct network
    # )

    # simulation_transaction = await rest_client.create_bcs_transaction(alice, TransactionPayload(entry_function))

    # simulation_result = await rest_client.simulate_transaction(simulation_transaction, alice)

    # success = simulation_result[0]['success']

    # signed_transaction = await rest_client.create_bcs_signed_transaction(
    #     alice,                           # Account with the private key
    #     TransactionPayload(entry_function),  # The payload from our transaction
    #     sequence_number=sequence_number  # Use the same sequence number as before
    # )

    # tx_hash = await rest_client.submit_bcs_transaction(signed_transaction)

    # await rest_client.wait_for_transaction(tx_hash)

    # transaction_details = await rest_client.transaction_by_hash(tx_hash)
    # success = transaction_details["success"]


if __name__ == "__main__":
    asyncio.run(main())
