const { getWasmTester } = require("./utils");
const { fetchMemory, fetchRegister } = require("../../vm/js/state");

describe("state", function () {
  describe("registers", function () {
    const nRegisters = 31;
    it("load", async function () {
      const circuit = await getWasmTester("registerLoad.test.circom");
      const addressSize = 5;
      const r = new Array(nRegisters).fill(null);
      for (let ii = 0; ii < nRegisters; ii++) {
        r[ii] = ii + 1;
      }
      for (let ii = 0; ii < nRegisters; ii++) {
        const address_bin = ii
          .toString(2)
          .padStart(addressSize, "0")
          .split("")
          .reverse();
        const w = await circuit.calculateWitness(
          { r: r, address_bin: address_bin },
          true
        );
        await circuit.assertOut(w, { out_dec: fetchRegister(r, ii) });
      }
    });
    it("store", async function () {
      const circuit = await getWasmTester("registerStore.test.circom");
      const addressSize = 5;
      const input = 255;
      const r = new Array(nRegisters).fill(null);
      for (let ii = 0; ii < nRegisters; ii++) {
        r[ii] = ii + 1;
      }
      for (let kk = 0; kk < 2; kk++) {
        for (let ii = 0; ii < nRegisters + 1; ii++) {
          const address_bin = ii
            .toString(2)
            .padStart(addressSize, "0")
            .split("")
            .reverse();
          const w = await circuit.calculateWitness(
            { in_dec: input, rIn: r, address_bin: address_bin, k: kk },
            true
          );
          let temp;
          if (ii > 0 && kk == 1) {
            temp = r[ii - 1];
            r[ii - 1] = input;
          }
          await circuit.assertOut(w, { rOut: r });
          if (ii > 0 && kk == 1) {
            r[ii - 1] = temp;
          }
        }
      }
    });
  });
});
