const M_ManToken = artifacts.require('./M_ManToken.sol');
const TestToken = artifacts.require('./TestToken.sol');
const TestOrg = artifacts.require('./TestOrg.sol');
const MaihuolangOrg = artifacts.require('./MaihuolangOrg.sol');
const Voting = artifacts.require('./Voting.sol');
const { SOKOL_U1, SOKOL_U2, SOKOL_U3, SOKOL_U4, SOKOL_FORMER_MMANTOKEN, SOKOL_FORMER_MAIHUOLANG } = process.env;
const { DAI_U1, DAI_U2, DAI_U3, DAI_U4, XDAI_FORMER_MMANTOKEN, XDAI_FORMER_MAIHUOLANG } = process.env;

module.exports = function(deployer, network, accounts) {
  console.log('////////////network:' + network + '////////////');
  // let rootUserAddr, teamAddr, marketing, investor;
  let tokenInheritFrom, orgInheritFrom;
  if (network === 'test') {
    rootUserAddr = accounts[1];
    teamAddr = accounts[98];
    marketing = accounts[99];
    investor = accounts[97];

    return deployer
      .deploy(TestToken, teamAddr, marketing, investor)
      .then(() => deployer.deploy(M_ManToken, TestToken.address, TestToken.address))
      .then(() => deployer.deploy(TestOrg, TestToken.address, rootUserAddr))
      .then(() => deployer.deploy(MaihuolangOrg, TestOrg.address, M_ManToken.address))
      .then(() => deployer.deploy(Voting, M_ManToken.address, MaihuolangOrg.address))
      .then(() => TestToken.deployed())
      .then(mmt => {
        mmt.setReward(TestOrg.address);
      })
      .then(() => M_ManToken.deployed())
      .then(mmt => {
        mmt.migrateBalance(rootUserAddr);
        mmt.setReward(MaihuolangOrg.address);
      });
  } else if (network === 'sokol-fork' || network === 'sokol') {
    rootUserAddr = SOKOL_U1;
    teamAddr = SOKOL_U2;
    marketing = SOKOL_U3;
    investor = SOKOL_U4;
    tokenInheritFrom = SOKOL_FORMER_MMANTOKEN;
    orgInheritFrom = SOKOL_FORMER_MAIHUOLANG;
  } else if (network === 'xdai-fork' || network === 'xdai') {
    rootUserAddr = DAI_U1;
    teamAddr = DAI_U2;
    marketing = DAI_U3;
    investor = DAI_U4;
    tokenInheritFrom = XDAI_FORMER_MMANTOKEN;
    orgInheritFrom = XDAI_FORMER_MAIHUOLANG;
    console.log('rootUserAddr', rootUserAddr);
  }
  console.log('tokenInheritFrom', tokenInheritFrom);
  console.log('orgInheritFrom', orgInheritFrom);
  deployer.deploy(M_ManToken, tokenInheritFrom, tokenInheritFrom).then(() =>
    deployer
      .deploy(MaihuolangOrg, orgInheritFrom, M_ManToken.address)
      .then(() => deployer.deploy(Voting, M_ManToken.address, MaihuolangOrg.address))
      .then(() => M_ManToken.deployed())
      .then(mmt => {
        mmt.migrateBalance(rootUserAddr);
        mmt.migrateBalance(teamAddr);
        mmt.migrateBalance(marketing);
        mmt.migrateBalance(investor);
        mmt.setReward(MaihuolangOrg.address);
      })
  );
};
