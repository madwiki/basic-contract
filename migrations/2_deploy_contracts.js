const MaihuoToken = artifacts.require('./MaihuoToken.sol');
const MaihuolangOrg = artifacts.require('./MaihuolangOrg.sol');
const Voting = artifacts.require('./Voting.sol');

module.exports = function(deployer, network, accounts) {
  if (network === 'test') {
    const rootUserAddr = accounts[1];
    const teamAddr = accounts[98];
    const marketing = accounts[99];

    deployer
      .deploy(MaihuoToken, teamAddr, marketing)
      .then(() =>
        deployer
          .deploy(MaihuolangOrg, MaihuoToken.address, rootUserAddr)
          .then(() => deployer.deploy(Voting, MaihuoToken.address, MaihuolangOrg.address))
      );
  }
};
