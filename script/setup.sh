#!/bin/bash

set -x

if ls *.ptau >/dev/null 2>&1; then
    rm *.ptau
fi

if ls *_000* >/dev/null 2>&1; then
    rm *_000*
fi

if ls circuit* >/dev/null 2>&1; then
    rm circuit*
fi

if ls *.sol >/dev/null 2>&1; then
    rm *.sol
fi

if ls *.wtns >/dev/null 2>&1; then
    rm *.wtns
fi

ls *.json | grep -v -E 'package.json' | xargs rm

PTAU=pot12_0000.ptau
PTAU1=pot12_0001.ptau
PTAU2=pot12_0002.ptau
PTAU3=pot12_0003.ptau
PTAUFIN=pot12_final.ptau
CH3=challenge_0003
RES3=response_0003
BCN=pot12_beacon.ptau
R1CS=circuit.r1cs
ZKEYFIN=circuit_final.zkey

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
cat <<EOT > circuit.circom
template Multiplier(n) {
	 signal private input a;
	 signal private input b;
	 signal output c;

	 signal int[n];

	 int[0] <==a*a + b;
	 for (var i=1; i<n; i++) {
	     int[i] <== int[i-1]*int[i-1] + b;
	 }

	 c <== int[n-1];
}

component main = Multiplier(1000);
EOT

# compile the circuit
npx circom circuit.circom --r1cs --wasm --sym -v

# view the informatino about the circuit
npx snarkjs r1cs info $R1CS

# print the constraints
npx snarkjs r1cs print $R1CS circuit.sym

# export r1cs to json
npx snarkjs r1cs export json $R1CS $R1CS.json
cat $_

# setup plonk
npx snarkjs plonk setup $R1CS $PTAUFIN $ZKEYFIN

# verify the final zkey
npx snarkjs zkey export verificationkey $ZKEYFIN verification_key.json

# calculate the witness
cat <<EOT > input.json
{"a": 3, "b": 11}
EOT

npx snarkjs wtns calculate circuit.wasm input.json witness.wtns

# debug the final witness calculation
npx snarkjs wtns debug circuit.wasm input.json witness.wtns circuit.sym --trigger --get --set

# create the proof
npx snarkjs plonk prove $ZKEYFIN witness.wtns proof.json public.json

# verify the proof
npx snarkjs plonk verify verification_key.json public.json proof.json

# turn the verifier into a smart contract
npx snarkjs zkey export solidityverifier $ZKEYFIN verifier.sol

# simulate a verification call
npx snarkjs zkey export soliditycalldata public.json proof.json
