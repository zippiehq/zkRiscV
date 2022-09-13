const fs = require("fs");
const { getWasmTester } = require("./utils");
const { textToMemoryTree } = require("../../vm/js/run");
const { multiStep_tree } = require("../../vm/js/vm");
const { buildMimcSponge } = require("circomlibjs");


describe("run", function () {
  this.timeout(30000);
  // const programNames = ["null", "hw"];
  const programNames = ["hw"];

  describe("tree", function () {
    let circuit;
    let mimcSponge;
    let mimcHash;
    let zeroElement = "21663839004416932945382355908790599225266501822907911457504978515578255421292"
    
    before(async function () {
      circuit = await getWasmTester("vmMultiStep_Tree.test.circom");
      mimcSponge = await buildMimcSponge();
      mimcHash = (left, right) => mimcSponge.F.toString(mimcSponge.multiHash([BigInt(left), BigInt(right)]))
    });
    
    for (let ii = 0; ii < programNames.length; ii++) {
      const programName = programNames[ii];
      it(programName, async function () {
        const filepath = `../vm/js/programs/${programName}.txt`;
        const nSteps = 8;
        const text = fs.readFileSync(filepath, "utf8");
        const pc0 = 0;
        const registers0 = new Array(31).fill(0);
        const mTree = textToMemoryTree(text, mimcHash, zeroElement);
        const refState = {
          mTree: mTree,
          r: registers0.slice(),
          pc: pc0,
        };
        const mRoot0 = mTree.root;
        const helpers = multiStep_tree(refState, { programSize: 16 }, nSteps);
        const w = await circuit.calculateWitness(
          {
            pcIn: pc0,
            rIn: registers0.slice(),
            mRoot0: mRoot0,
            ...helpers,
          },
          true
        );
        await circuit.assertOut(w, {
          mRoot1: refState.mTree.root,
          rOut: refState.r,
          pcOut: refState.pc,
        });
        await circuit.loadConstraints();
        console.log("constraints: " + circuit.constraints.length);
      });
    }
  });
});