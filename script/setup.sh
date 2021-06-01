#!/bin/bash

set -x

cd "$(dirname "$0")"
cd ..

if [[ -e ./build ]]; then
    rm -rf build
fi

mkdir -p ./build

# if ls *.ptau >/dev/null 2>&1; then
#     rm *.ptau
# fi

# if ls *_000* >/dev/null 2>&1; then
#     rm *_000*
# fi

# if ls circuit* >/dev/null 2>&1; then
#     rm circuit*
# fi

# if ls *.sol >/dev/null 2>&1; then
#     rm *.sol
# fi

# if ls *.wtns >/dev/null 2>&1; then
#     rm *.wtns
# fi

# ls *.json | grep -v -E 'package.json' | xargs rm

PTAU=build/pot12_0000.ptau
PTAU1=build/pot12_0001.ptau
PTAU2=build/pot12_0002.ptau
PTAU3=build/pot12_0003.ptau
PTAUFIN=build/pot12_final.ptau
CH3=build/challenge_0003
RES3=build/response_0003
BCN=build/pot12_beacon.ptau
R1CS=build/circuit.r1cs
ZKEYFIN=build/circuit_final.zkey

# start a new powers of tau ceremony
npx snarkjs powersoftau new bn128 12 $PTAU -v

# contribute to the ceremony (will open a prompt)
npx snarkjs powersoftau contribute $PTAU $PTAU1 --name="First contributino" -v

# provide a second contribution
npx snarkjs powersoftau contribute $PTAU1 $PTAU2 --name="Second contributin" -v -e="some random text"

# provide a third contribution using third party software
npx snarkjs powersoftau export challenge $PTAU2 $CH3
npx snarkjs powersoftau challenge contribute bn128 $CH3 $RES3 -e="some random text"
npx snarkjs powersoftau import response $PTAU2 $RES3 $PTAU3 -n="Third contribution"

# verify the protocol so far
npx snarkjs powersoftau verify $PTAU3

# apply a random beacon
npx snarkjs powersoftau beacon $PTAU3 $BCN 0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f 10 -n="Final Beacon"

# prepare phase 2
npx snarkjs powersoftau prepare phase2 $BCN $PTAUFIN -v

# verify the final ptau
npx snarkjs powersoftau verify $PTAUFIN

# create the circuit
cat <<EOT > build/circuit.circom
template IsZero() {
    signal input in;
    signal output out;

    signal inv;

    inv <-- in!=0 ? 1/in : 0;

    out <== -in*inv +1;
    in*out === 0;
}

template IsEqual() {
    signal input in[2];
    signal output out;

    component isz = IsZero();

    in[1] - in[0] ==> isz.in;

    isz.out ==> out;
}


component main = IsEqual();
EOT

# compile the circuit
npx circom build/circuit.circom -r build/circuit.r1cs -w build/circuit.wasm -s build/circuit.sym -v

# view the informatino about the circuit
npx snarkjs r1cs info $R1CS

# print the constraints
npx snarkjs r1cs print $R1CS build/circuit.sym

# export r1cs to json
npx snarkjs r1cs export json $R1CS $R1CS.json
cat $_

# setup plonk
npx snarkjs plonk setup $R1CS $PTAUFIN $ZKEYFIN

# verify the final zkey
npx snarkjs zkey export verificationkey $ZKEYFIN build/verification_key.json

# calculate the witness
cat <<EOT > build/input.json
{"in": [1,1]}
EOT

npx snarkjs wtns calculate build/circuit.wasm build/input.json build/witness.wtns

# debug the final witness calculation
npx snarkjs wtns debug build/circuit.wasm build/input.json build/witness.wtns build/circuit.sym --trigger --get --set

# create the proof
npx snarkjs plonk prove $ZKEYFIN build/witness.wtns build/proof.json build/public.json

# verify the proof
time npx snarkjs plonk verify build/verification_key.json build/public.json build/proof.json

# turn the verifier into a smart contract
# npx snarkjs zkey export solidityverifier $ZKEYFIN verifier.sol

# simulate a verification call
# npx snarkjs zkey export soliditycalldata public.json proof.json
