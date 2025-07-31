Monday:

- Script to deploy eth contracts
- Script to create the eth src
- Script to create the eth dst

- Script to deploy the aptos contracts
- Script to create the aptos src
- Script to create the aptos dst

- Test with scripts transferning assets between aptos and eth

Tuesday:

- Get multifill working 
- Create relayer implementation

Wednesday: 

- Create other implementation of the contract on other chains??

Thursday:

- Cleanup 
- UI ?????





- [x] Deploy aptos with scripts and get necessary addresses
- [x] Create escrow (src/dst) on aptos with scripts
- [x] Deploy eth with scripts and get necessary addresses
- [-] Create escrow (src/dst) on eth with scripts
- [x] Ensure able to make transactions with scripts

- [_] Support relay paying the incentive on aptos and modify scripts
- [_] Support multi agent transaction on aptos
- [_] Write tests for aptos

- [_] Make general submission of transactions on aptos in typescript
- [_] Get necessary data from aptos logs
- [_] Get necessary data from eth logs
- [_] Support signing transaction in js for aptos and eth


aptos move publish
aptos node run-local-testnet --with-indexer-api  
aptos move publish
aptos account fund-with-faucet 
aptos move run-script --compiled-script-path ./build/order-factory/bytecode_scripts/main.mv 
aptos move run-script --compiled-script-path ./build/order-factory/bytecode_scripts/create_order.mv   


Create empty order with incentive funds, funds can be claimed until the order has had details added. User transaction then submitted (with min incentive) which then fills the empty order. This way we don't need more than one participant in a single transaction, simplifying the process.