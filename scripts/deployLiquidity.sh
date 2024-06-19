#!/bin/bash

# factoryAddr=$(cat ../deployment.json | jq -r .v2Factory)
# factoryAddr=0xA055ED7b2e3aE933E2Ca4bD8655A65079B5A26aB
echo "The factory is at $factoryAddr"

if [ $# -lt 2 ]; then
    echo "Missing arguments"
    exit 1
fi

RPC_URL=$1
FACTORY_ADDR=$2
PRVKEY=$3
ROUTER=$4
echo "RPC_URL: $RPC_URL"
echo "FACTORY_ADDR: $FACTORY_ADDR"
echo "PRVKEY: $PRVKEY"
echo "ROUTER: $ROUTER"

# suave admin default
# anvil[0]
walletAddr=$(cast wallet address $PRVKEY)
echo "Connected to RPC: $RPC_URL"

### deployFactory deploys a factory contract.
### args: ()
### example: deployFactory
### "returns" by setting $deployFactoryReturn
deployFactory() {
    git clone https://github.com/Uniswap/v2-core.git /tmp/univ2-core
    MARK=$PWD
    cd /tmp/univ2-core
    forge build

    deployFactoryReturn=$(
        forge create --json -r $RPC_URL --legacy --private-key "$PRVKEY" contracts/UniswapV2Factory.sol:UniswapV2Factory --constructor-args $walletAddr | jq -r .deployedTo
    )
    rm -rf /tmp/univ2-core
    cd $MARK
}

if [ -z "$factoryAddr" ]; then
    echo "Factory not found. Deploying..."
    deployFactory
    factoryAddr=$deployFactoryReturn
    echo "Factory deployed at $factoryAddr"
fi

### deployToken deploys an ERC20 token, minting the sender a balance of 1e27 tokens. Give it a letter like "A" or "B" or "C" to distinguish between tokens.
### args: (string tokenLetter)
### example: deployToken "A"
### "returns" by setting $deployTokenReturn
deployToken() {
    deployTokenReturn=$(
        forge create --json -r $RPC_URL --legacy --private-key "$PRVKEY" src/Token.sol:Token --constructor-args "$1"  | jq -r .deployedTo
    )
}

assertOkStatus() {
    if [[ "$1" != *"0x1"* ]]; then
        echo "Failed. Exiting."
        exit 1
    fi
}

### deployLiquidityPair deploys a liquidity pair contract given two token addresses.
### args: (string tokenA, string tokenB)
### example: deployLiquidityPair $tokenA $tokenB
### to get the LP contract address, call `getPair` on the factory contract with the two token addresses.
deployLiquidityPair() {
    status=$(cast send -r $RPC_URL --legacy --json --private-key "$PRVKEY" "$factoryAddr" "createPair(address,address)" "$1" "$2" | jq .status)
    assertOkStatus "$status"
}

### getPair gets the pair contract address for a given pair of tokens.
### args: (string tokenA, string tokenB)
### example: getPair $tokenA $tokenB
### "returns" by setting $getPairReturn
getPair() {
    getPairReturn=$(cast call -r $RPC_URL $factoryAddr "getPair(address,address)(address)" $1 $2)
}

### provisionLiquidity mints liquidity tokens for a given pair contract, by sending the pair contract some of each token and then calling mint.
### args: (string tokenA, string tokenB, string pairAddr, string amountA, string amountB)
### example: provisionLiquidity $tokenA $pair_AB '100 ether'
provisionLiquidity() {
    token0=$1
    token1=$2
    pairAddr=$3
    amountA=$4
    amountB=$5

    status=$(cast send -r $RPC_URL --legacy --gas-limit 100000 --gas-price '69 gwei' --json --private-key $PRVKEY $token0 "transfer(address,uint256)" "$pairAddr" "$amountA")
    assertOkStatus "$status"
    echo "Sent $amountA of Token0 to $pairAddr"

    status=$(cast send -r $RPC_URL --legacy --gas-limit 100000 --gas-price '69 gwei' --json --private-key $PRVKEY $token1 "transfer(address,uint256)" "$pairAddr" "$amountB")
    assertOkStatus "$status"
    echo "Sent $amountB of Token1 to $pairAddr"

    sleep 1
    status=$(cast send -r $RPC_URL --legacy --gas-limit 100000 --gas-price '69 gwei' --json --private-key $PRVKEY $pairAddr "mint(address)" $walletAddr)
    assertOkStatus "$status"
    echo "Minted LP tokens on $pairAddr"
}

approveMaxTokensToRouter() {
    token=$1
    echo "Approving max tokens to router for $token"
    amount=115792089237316195423570985008687907853269984665640564039457584007913129639935
    status=$(cast send -r $RPC_URL --private-key "$PRVKEY" $token "approve(address,uint256)" $ROUTER $amount | jq .status)
    assertOkStatus "$status"
}

routerWhitelistTokens() {
    tokens=$1
    echo "Whitelisting tokens on router for $tokens"
    status=$(cast send -r $RPC_URL --private-key "$PRVKEY" $ROUTER "setTrustedTokens(address[])" $tokens | jq .status)
    assertOkStatus "$status"
}


# create new tokens
echo "Creating tokens..."
deployToken "A"
tokenA=$deployTokenReturn
deployToken "B"
tokenB=$deployTokenReturn
deployToken "C"
tokenC=$deployTokenReturn
echo "tokenA: $tokenA"
echo "tokenB: $tokenB"
echo "tokenC: $tokenC"

# create liquidity pairs
echo "Creating liquidity pairs..."
deployLiquidityPair $tokenA $tokenB
deployLiquidityPair $tokenA $tokenC
deployLiquidityPair $tokenB $tokenC

# wait
sleep 1

# retrieve pair addresses
getPair $tokenA $tokenB
pair_AB=$getPairReturn
getPair $tokenA $tokenC
pair_AC=$getPairReturn
getPair $tokenB $tokenC
pair_BC=$getPairReturn
echo "pair A/B: $pair_AB"
echo "pair A/C: $pair_AC"
echo "pair B/C: $pair_BC"

echo "tokenA: $tokenA"
echo "tokenB: $tokenB"
echo "tokenC: $tokenC"

# fund pairs w/ tokens & mint LP tokens
provisionLiquidity $tokenA $tokenB $pair_AB '500 ether' '50 ether'
provisionLiquidity $tokenA $tokenC $pair_AC '500 ether' '50 ether'
provisionLiquidity $tokenB $tokenC $pair_BC '500 ether' '50 ether'

echo "approving tokens"
approveMaxTokensToRouter $tokenA
approveMaxTokensToRouter $tokenB
approveMaxTokensToRouter $tokenC

echo "whitelisting tokens"
routerWhitelistTokens "[$tokenA, $tokenB, $tokenC]"

# write results to deployment-{timestamp}.json
echo "{
    \"v2Factory\": \"$factoryAddr\",
    \"tokenA\": \"$tokenA\",
    \"tokenB\": \"$tokenB\",
    \"tokenC\": \"$tokenC\",
    \"pairAB\": \"$pair_AB\",
    \"pairAC\": \"$pair_AC\",
    \"pairBC\": \"$pair_BC\"
}" > ../deployment-test.json
