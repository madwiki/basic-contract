const Org = artifacts.require("Org");

module.exports = function(deployer) {
  deployer.deploy(Org);
};
