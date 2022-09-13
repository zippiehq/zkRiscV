pragma circom 2.0.2;

include "./lib/muxes.circom";
include "./lib/bitify.circom";
include "./constants.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/binsum.circom";

template RV32I_Register_Load() {
    signal input address_bin[R_ADDRESS_SIZE()];
    signal input r[N_REGISTERS()];
    signal output out_dec;

    component mux = Mux5();
    mux.c[0] <== 0;
    for (var ii = 0; ii < N_REGISTERS(); ii++) mux.c[1 + ii] <== r[ii];
    for (var ii = 0; ii < R_ADDRESS_SIZE(); ii++) mux.s[ii] <== address_bin[ii];

    out_dec <== mux.out;
}

template RV32I_Register_Store() {
    signal input address_bin[R_ADDRESS_SIZE()];
    signal input in_dec;
    signal input k;
    signal input rIn[N_REGISTERS()];
    signal output rOut[N_REGISTERS()];

    component imux = IMux5();
    for (var ii = 0; ii < R_ADDRESS_SIZE(); ii++) imux.s[ii] <== address_bin[ii];
    imux.in <== k;

    component mux[N_REGISTERS()];
    for (var ii = 0; ii < N_REGISTERS(); ii++) mux[ii] = Mux1();
    for (var ii = 0; ii < N_REGISTERS(); ii++) {
        mux[ii].s <== imux.out[ii + 1];
        mux[ii].c[0] <== rIn[ii];
        mux[ii].c[1] <== in_dec;
        rOut[ii] <== mux[ii].out;
    }
}

// component main = RV32I_Register_Store();
