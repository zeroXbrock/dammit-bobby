#!/bin/bash

suave-geth --version 2>/dev/null 1>/dev/null
if [ $? -ne 0 ]; then
    echo "suave-geth is not installed. pls build it and copy to /usr/local/bin/"
    exit 1
fi

echo "Deploying Bob..."
PRVKEY=91ab9a7e53c220e6210460b65a7a3bb2ca181412a8a7b43ff336b3df1737ce12
walletAddr=$(cast wallet address $PRVKEY)
echo "Wallet address: $walletAddr"
contractAddr=$(forge create --json -r http://localhost:8545 --private-key $PRVKEY src/Bob.sol:BobTheBuilder | jq -r .deployedTo)
suave-geth spell conf-request --kettle-address 0xb5feafbdd752ad52afb7e1bd2e40432a485bbb7f --private-key $PRVKEY $contractAddr "findArbs(address)" "($walletAddr)"
