const MaihuoToken = artifacts.require('./MaihuoToken.sol');
const MaihuolangOrg = artifacts.require('./MaihuolangOrg.sol');
const Voting = artifacts.require('./Voting.sol');
const { SOKOL_U1, SOKOL_U2, SOKOL_U3, SOKOL_U4 } = process.env;
const { DAI_U1, DAI_U2, DAI_U3 } = process.env;

module.exports = function(deployer, network, accounts) {
  console.log('////////////network:' + network + '////////////');
  let rootUserAddr, teamAddr, marketing, investor;
  if (network === 'test') {
    rootUserAddr = accounts[1];
    teamAddr = accounts[98];
    marketing = accounts[99];
    investor = accounts[97];
  } else if (network === 'sokol-fork' || network === 'sokol') {
    rootUserAddr = SOKOL_U1;
    teamAddr = SOKOL_U2;
    marketing = SOKOL_U3;
    investor = SOKOL_U4;
  } else if (network === 'dai-fork' || network === 'dai') {
    rootUserAddr = DAI_U1;
    teamAddr = DAI_U2;
    marketing = DAI_U3;
  }
  deployer.deploy(MaihuoToken, teamAddr, marketing, investor).then(() =>
    deployer
      .deploy(MaihuolangOrg, MaihuoToken.address, rootUserAddr)
      .then(() => deployer.deploy(Voting, MaihuoToken.address, MaihuolangOrg.address))
      .then(() => MaihuoToken.deployed())
      .then(mht => mht.setReward(MaihuolangOrg.address))
  );
};
