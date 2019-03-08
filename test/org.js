var Org = artifacts.require("./Org.sol");

contract("Org", function(accounts) {
  let org;

  before(async () => {
    org = await Org.deployed();
    const users = [];
    for (let index = 0; index < 100000; index++) {
      const act = await web3.eth.personal.newAccount(index);
      users.push(act);
    }
    for (let num = 0; num < 1000; num++) {
      await org.batchRegister(users.slice(100 * num, 100 * (num + 1)));
    }
    console.log("users", users.length);
  });

  it("test", async function() {
    const userArray = await org.getUserArray();
    console.log("userArray", userArray);
  });
});
