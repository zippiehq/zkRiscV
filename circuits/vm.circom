pragma circom 2.0.2;

include "./lib/bitify.circom";
include "./lib/pack.circom";
include "./lib/merkleTree.circom";
include "./decoder.circom";
include "./state.circom";
include "./alu.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/gates.circom";
include "../node_modules/circomlib/circuits/mimcsponge.circom";

// TODO: make names more consistent
// TODO: load vs fetch
// TODO: check r and m values are never going to be out of bounds [!]
//          How to handle input state having values out of bounds [?]
// TODO: add merklelized state [!]
// TODO: make things cleaner than calling constant functions all the time
// TODO: spec cool memory optimizations
// TODO: handle invalid instruction [?]

function LOG2_PROGRAM_SIZE() {
    return 6;
}

function LOG2_DATA_SIZE() {
    return 6;
}

function PROGRAM_SIZE() {
    return 2 ** LOG2_PROGRAM_SIZE();
}

function DATA_SIZE() {
    return 2 ** LOG2_DATA_SIZE();
}

// Flat memory, harvard model constants
function MEMORY_SIZE_FLAT() {
    return PROGRAM_SIZE() + DATA_SIZE();
}

function PROGRAM_START() {
    return 0;
}

function PROGRAM_END() {
    return PROGRAM_SIZE();
}

function DATA_START() {
    return PROGRAM_END();
}

function DATA_END() {
    return MEMORY_SIZE_FLAT();
}


template MPointer() {
    signal input imm_dec;
    signal input rs1Value_dec;
    signal output out_dec;
    out_dec <== rs1Value_dec + imm_dec;
}

template K_Parser() {
    signal input instructionType_bin[INSTRUCTION_TYPE_SIZE()];
    signal input opcode_bin_6_2[OPCODE_6_2_SIZE()];
    signal output kM;
    signal output kR;

    component mAnd = AND();
    mAnd.a <== instructionType_bin[2];
    mAnd.b <== opcode_bin_6_2[3];
    kM <== mAnd.out;

    component rNand = NAND();
    rNand.a <== instructionType_bin[0];
    rNand.b <== instructionType_bin[1];
    component rNot = NOT();
    rNot.in <== opcode_bin_6_2[3];
    component rMux = Mux1();
    rMux.c[0] <== rNand.out;
    rMux.c[1] <== rNot.out;
    rMux.s <== instructionType_bin[2];
    kR <== rMux.out;
}

template NewRDValueDecider() {
    signal input aluOut_dec;
    signal input mOut_dec;
    signal input instructionType_bin[INSTRUCTION_TYPE_SIZE()];
    signal input opcode_bin_6_2[OPCODE_6_2_SIZE()];
    signal output out_dec;

    component not = NOT();
    not.in <== opcode_bin_6_2[3];
    component and = AND();
    and.a <== not.out;
    and.b <== instructionType_bin[2];

    component mux = Mux1();
    mux.c[0] <== aluOut_dec;
    mux.c[1] <== mOut_dec;
    mux.s <== and.out;

    out_dec <== mux.out;
}

// programSize: number of instructions in program
template VMStep_Tree(memoryDepth, programSize) {

    signal input pcIn;
    signal input rIn[N_REGISTERS()];
    signal input instruction;
    signal input instructionProof[memoryDepth];
    signal input m;
    signal input mProof[memoryDepth];
    signal input mRoot0;
    signal output pcOut;
    signal output rOut[N_REGISTERS()];
    signal output mRoot1;

    // check instruction merkle proof
    component pcIn_bin = Num2Bits(memoryDepth + 2);
    pcIn_bin.in <== pcIn;
    component instructionMerkleChecker = MerkleTreeChecker(memoryDepth);
    instructionMerkleChecker.leaf <== instruction;
    instructionMerkleChecker.root <== mRoot0;
    
    for (var ii = 0; ii < memoryDepth; ii++) {
        instructionMerkleChecker.pathElements[ii] <== instructionProof[ii];
        instructionMerkleChecker.pathIndices[ii] <== pcIn_bin.out[2 + ii];
    }

    // decode instruction
    component instruction_bin = Num2Bits(INSTRUCTION_SIZE_BITS());
    instruction_bin.in <== instruction;

    component decoder = RV32I_Decoder();
    for (var ii = 0; ii < INSTRUCTION_SIZE_BITS(); ii++) decoder.instruction_bin[ii] <== instruction_bin.out[ii];

    // load register data
    component rs1Loader = RV32I_Register_Load();
    component rs2Loader = RV32I_Register_Load();

    for (var ii = 0; ii < R_ADDRESS_SIZE(); ii++) {
        rs1Loader.address_bin[ii] <== decoder.rs1_bin[ii];
        rs2Loader.address_bin[ii] <== decoder.rs2_bin[ii];
    }

    for (var ii = 0; ii < N_REGISTERS(); ii++) {
        rs1Loader.r[ii] <== rIn[ii];
        rs2Loader.r[ii] <== rIn[ii];
    }

    signal rs1Value_dec;
    signal rs1Value_bin[R_SIZE()];
    signal rs2Value_dec;
    signal rs2Value_bin[R_SIZE()];

    rs1Value_dec <== rs1Loader.out_dec;
    rs2Value_dec <== rs2Loader.out_dec;

    component RValueBin[2];
    for (var ii = 0; ii < 2; ii++) RValueBin[ii] = Num2Bits(R_SIZE());
    RValueBin[0].in <== rs1Value_dec;
    RValueBin[1].in <== rs2Value_dec;

    for (var ii = 0; ii < R_SIZE(); ii++) {
        rs1Value_bin[ii] <== RValueBin[0].out[ii];
        rs2Value_bin[ii] <== RValueBin[1].out[ii];
    }

    // compute
    component alu = ALU();
    for (var ii = 0; ii < INSTRUCTION_TYPE_SIZE(); ii++) alu.instructionType_bin[ii] <== decoder.instructionType_bin[ii];
    for (var ii = 0; ii < OPCODE_6_2_SIZE(); ii++) alu.opcode_bin_6_2[ii] <== decoder.opcode_bin_6_2[ii];
    for (var ii = 0; ii < F3_SIZE(); ii++) alu.f3_bin[ii] <== decoder.f3_bin[ii];
    for (var ii = 0; ii < F7_SIZE(); ii++) alu.f7_bin[ii] <== decoder.f7_bin[ii];
    for (var ii = 0; ii < R_SIZE(); ii++) {
        alu.rs1Value_bin[ii] <== rs1Value_bin[ii];
        alu.rs2Value_bin[ii] <== rs2Value_bin[ii];
    }
    alu.pcIn_dec <== pcIn;
    alu.rs1Value_dec <== rs1Value_dec;
    alu.rs2Value_dec <== rs2Value_dec;
    alu.imm_dec <== decoder.imm_dec;
    pcOut <== alu.pcOut_dec;

    // parse ks
    component ks = K_Parser();
    for (var ii = 0; ii < INSTRUCTION_TYPE_SIZE(); ii++) ks.instructionType_bin[ii] <== decoder.instructionType_bin[ii];
    for (var ii = 0; ii < OPCODE_6_2_SIZE(); ii++) ks.opcode_bin_6_2[ii] <== decoder.opcode_bin_6_2[ii];

    // memory vs alu output
    component newRDValueDecider = NewRDValueDecider();
    newRDValueDecider.aluOut_dec <== alu.out_dec;
    newRDValueDecider.mOut_dec <== m;
    for (var ii = 0; ii < INSTRUCTION_TYPE_SIZE(); ii++) newRDValueDecider.instructionType_bin[ii] <== decoder.instructionType_bin[ii];
    for (var ii = 0; ii < OPCODE_6_2_SIZE(); ii++) newRDValueDecider.opcode_bin_6_2[ii] <== decoder.opcode_bin_6_2[ii];

    // store into register
    component rStore = RV32I_Register_Store();
    rStore.in_dec <== newRDValueDecider.out_dec;
    rStore.k <== ks.kR;
    for (var ii = 0; ii < R_ADDRESS_SIZE(); ii++) rStore.address_bin[ii] <== decoder.rd_bin[ii];
    for (var ii = 0; ii < N_REGISTERS(); ii++) rStore.rIn[ii] <== rIn[ii];
    for (var ii = 0; ii < N_REGISTERS(); ii++) rOut[ii] <== rStore.rOut[ii];

    // compute new mRoot
    component mPointer = MPointer();
    mPointer.rs1Value_dec <== rs1Value_dec;
    mPointer.imm_dec <== decoder.imm_dec;

    /*
    (pathIndices, leaf)
    if loadind, (mPointer, m)
    else if storing, (mPointer, rs2 % 256)
    else (pcIn, instruction)
     */

    component rs2Value_7_0_dec = Bits2Num(M_SLOT_SIZE());
    for (var ii = 0; ii < M_SLOT_SIZE(); ii++) rs2Value_7_0_dec.in[ii] <== rs2Value_bin[ii];
    
    // TODO: abstract cleanly
    // TODO: check this again

    component mPathIndices = Num2Bits(memoryDepth);
    mPathIndices.in <== mPointer.out_dec - 3 * programSize * decoder.instructionType_bin[2];

    component mMerkleTree0 = MerkleTree(memoryDepth);
    mMerkleTree0.leaf <== m;

    for (var ii = 0; ii < memoryDepth; ii++) {
        mMerkleTree0.pathElements[ii] <== mProof[ii];
        mMerkleTree0.pathIndices[ii] <== mPathIndices.out[ii];
    }

    component mr0_mrMux = Mux1();
    mr0_mrMux.c[0] <== mRoot0;
    mr0_mrMux.c[1] <== mMerkleTree0.root;
    mr0_mrMux.s <== decoder.instructionType_bin[2];

    mr0_mrMux.out === mRoot0;

    component m_rs2Mux = Mux1();
    m_rs2Mux.c[0] <== m;
    m_rs2Mux.c[1] <== rs2Value_7_0_dec.out;
    m_rs2Mux.s <== decoder.opcode_bin_6_2[3];

    component mMerkleTree1 = MerkleTree(memoryDepth);
    mMerkleTree1.leaf <== m_rs2Mux.out;

     for (var ii = 0; ii < memoryDepth; ii++) {
        mMerkleTree1.pathElements[ii] <== mProof[ii];
        mMerkleTree1.pathIndices[ii] <== mPathIndices.out[ii];
    }

    component mRootMux = Mux1();
    mRootMux.c[0] <== mRoot0;
    mRootMux.c[1] <== mMerkleTree1.root;
    mRootMux.s <== decoder.instructionType_bin[2];

    mRoot1 <== mRootMux.out;

}

template VMMultiStep_Tree(n, memoryDepth, programSize) {
    
    signal input pcIn;
    signal input rIn[N_REGISTERS()];
    signal input instructions[n];
    signal input instructionProofs[n][memoryDepth];
    signal input ms[n];
    signal input mProofs[n][memoryDepth];
    signal input mRoot0;
    signal output pcOut;
    signal output rOut[N_REGISTERS()];
    signal output mRoot1;

    component steps[n];
    for (var ii = 0; ii < n; ii++) steps[ii] = VMStep_Tree(memoryDepth, programSize);
    
    steps[0].pcIn <== pcIn;
    for (var ii = 0; ii < N_REGISTERS(); ii++) {
        steps[0].rIn[ii] <== rIn[ii];
    }
    steps[0].instruction <== instructions[0];
    steps[0].m <== ms[0];
    for (var ii = 0; ii < memoryDepth; ii++) {
        steps[0].instructionProof[ii] <== instructionProofs[0][ii];
        steps[0].mProof[ii] <== mProofs[0][ii];
    }
    steps[0].mRoot0 <== mRoot0;

    for (var ii = 1; ii < n; ii++) {
        steps[ii].pcIn <== steps[ii - 1].pcOut;
        for (var jj = 0; jj < N_REGISTERS(); jj++) {
            steps[ii].rIn[jj] <== steps[ii - 1].rOut[jj];
        }
        steps[ii].instruction <== instructions[ii];
        steps[ii].m <== ms[ii];
        for (var jj = 0; jj < memoryDepth; jj++) {
            steps[ii].instructionProof[jj] <== instructionProofs[ii][jj];
            steps[ii].mProof[jj] <== mProofs[ii][jj];
        }
        steps[ii].mRoot0 <== steps[ii - 1].mRoot1;
    }

    pcOut <== steps[n - 1].pcOut;
    for (var jj = 0; jj < N_REGISTERS(); jj++) {
        rOut[jj] <== steps[n - 1].rOut[jj];
    }
    mRoot1 <== steps[n - 1].mRoot1;

}

template StateHash_Tree() {
    signal input pc;
    signal input r[N_REGISTERS()];
    signal input mRoot;
    signal output out;

    var n32BitVars = 1 + N_REGISTERS();
    var packingVars32[3] = getPackingVars(n32BitVars, R_SIZE());
    var nPacks32 = packingVars32[1];

    component packs32bits = Pack(n32BitVars, R_SIZE());
    packs32bits.in[0] <== pc;
    for (var ii = 0; ii < N_REGISTERS(); ii++) packs32bits.in[1 + ii] <== r[ii];
    
    component mimc = MiMCSponge(1 + nPacks32, 220, 1);
    for (var ii = 0; ii < nPacks32; ii++) mimc.ins[ii] <== packs32bits.out[ii];
    mimc.ins[nPacks32] <== mRoot;
    mimc.k <== 0;
    out <== mimc.outs[0];

}

template ValidVMMultiStep_Tree(n, memoryDepth, programSize, rangeCheck) {
    signal input pcIn;
    signal input rIn[N_REGISTERS()];
    signal input instructions[n];
    signal input instructionProofs[n][memoryDepth];
    signal input ms[n];
    signal input mProofs[n][memoryDepth];
    signal input mRoot0;
    signal input root0;
    signal input root1;

    // component pcRangeCheck;
    component rRangeCheck;
    component instructionRangeCheck;
    component mRangeCheck;

    if (rangeCheck == 1) {
        // pcRangeCheck = AssertInBitRange(R_SIZE());
        // pcRangeCheck.in <== pcIn;
        rRangeCheck = MultiAssertInBitRange(N_REGISTERS(), R_SIZE());
        for (var ii = 0; ii < N_REGISTERS(); ii++) rRangeCheck.in[ii] <== rIn[ii];
        instructionRangeCheck = MultiAssertInBitRange(n, R_SIZE());
        for (var ii = 0; ii < n; ii++) instructionRangeCheck.in[ii] <== instructions[ii];
        mRangeCheck = MultiAssertInBitRange(n, M_SLOT_SIZE());
        for (var ii = 0; ii < n; ii++) mRangeCheck.in[ii] <== ms[ii];
    }

    component stateHash0 = StateHash_Tree();
    stateHash0.pc <== pcIn;
    for (var ii = 0; ii < N_REGISTERS(); ii++) stateHash0.r[ii] <== rIn[ii];
    stateHash0.mRoot <== mRoot0;

    root0 === stateHash0.out;

    component vm = VMMultiStep_Tree(n, memoryDepth, programSize);
    vm.pcIn <== pcIn;
    for (var ii = 0; ii < N_REGISTERS(); ii++) vm.rIn[ii] <== rIn[ii];
    vm.mRoot0 <== mRoot0;
    for (var ii = 0; ii < n; ii++) {
        vm.instructions[ii] <== instructions[ii];
        vm.ms[ii] <== ms[ii];
        for (var jj = 0; jj < n; jj++) {
            vm.instructionProofs[ii][jj] <== instructionProofs[ii][jj];
            vm.mProofs[ii][jj] <== mProofs[ii][jj];
        }
    }

    component stateHash1 = StateHash_Tree();
    stateHash1.pc <== vm.pcOut;
    for (var ii = 0; ii < N_REGISTERS(); ii++) stateHash1.r[ii] <== vm.rOut[ii];
    stateHash1.mRoot <== vm.mRoot1;

    root1 === stateHash1.out;

}

// component main {public [root0, root1]} = ValidVMMultiStep_Flat(1, 0);
// component main = ValidVMMultiStep_Flat(160, 0);

/**

******** CONSTRAINS ********

ALU         1823
    CompW   1823
    LoadI   1
    Jump    3
    Branch  6

Decoder 13

State   2183
    Memory64_Load1  85
    Memory64_Load4  340
    Memory64_Store1 133
    RV32I_Register_Load     39
    RV32I_Register_Store    62

VMStep_Flat     2683
StateHash_Flat  5940

BitwiseXOR32    32
BitwiseOR32     32
BitwiseAND32    32

AssertInBitRange32  32

LeftShift1      0
RightShift32_1  32
VariableShift32_right
VariableShift32_left
VariableBinShift32_right
VariableBinShift32_left

ValidVMMultiStep_Flat_160_0 441160

 */
