const MaihuoToken = artifacts.require('./MaihuoToken.sol');
const MaihuolangOrg = artifacts.require('./MaihuolangOrg.sol');
const Voting = artifacts.require('./Voting.sol');
var Web3 = require('web3');
const web3 = new Web3(new Web3.providers.HttpProvider('http://127.0.0.1:7545'));

contract('Maihuolang', function(accounts) {
  let mht;
  let org;
  let voting;
  const userModel = {
    children: [],
    parent: '0x0000000000000000000000000000000000000000',
    self: '0x0000000000000000000000000000000000000000',
    invitor: '0x0000000000000000000000000000000000000000',
    rank: 0,
    level: 0,
    frozen: false,
    releaseAt: 0,
    rank1Received: 0,
    rank1Delivered: 0,
  };
  const rootUserAddr = accounts[1];
  const level2user1 = accounts[97];
  let caseBuyer, caseSeller, caseArbiter;

  before(async () => {
    mht = await MaihuoToken.deployed();
    org = await MaihuolangOrg.deployed();
    voting = await Voting.deployed();
  });

  it('check _rootUserAddr(检查预设顶层地址)', async function() {
    const rootUser = await onchainUser(rootUserAddr);
    assert.deepEqual(
      rootUser,
      offchainUser({
        self: rootUserAddr,
        rank: 9,
        level: 1,
        rank1Received: 81,
        rank1Delivered: 27,
      }),
      'incorrect user!'
    );
  });

  it('set reward address(设置奖励地址)', async function() {
    await mht.setReward(org.address);
    const rewardAddr = await mht.rewardAddr();
    assert.equal(rewardAddr, org.address, 'fail!');
  });

  it('init user(初始化用户，确认等级)', async function() {
    await org.initUser(rootUserAddr, level2user1);
    const childUser = await onchainUser(level2user1);
    assert.deepEqual(
      offchainUser({
        parent: rootUserAddr,
        self: level2user1,
        rank: 9,
        level: 2,
        rank1Received: 81,
        rank1Delivered: 27,
      }),
      childUser,
      'incorrect user!'
    );
  });

  it('batch init user by one line(批量初始化一条用户线)', async function() {
    const parents = accounts.slice(1, 9);
    const targets = accounts.slice(2, 10);
    await org.batchInitUsers(parents, targets);
    const childUsers = [];
    for (let index = 0; index < targets.length; index++) {
      childUsers[index] = await org.userMap(targets[index]);
      assert.equal(childUsers[index].parent, parents[index], 'fail parent:' + childUsers[index]);
    }
    assert.equal(childUsers[0].level, 2, 'fail level at user:' + 0);
    assert.equal(childUsers[1].level, 3, 'fail level at user:' + 1);
    assert.equal(childUsers[2].level, 4, 'fail level at user:' + 2);
    assert.equal(childUsers[3].level, 5, 'fail level at user:' + 3);
    assert.equal(childUsers[4].level, 6, 'fail level at user:' + 4);
    assert.equal(childUsers[5].level, 7, 'fail level at user:' + 5);
    assert.equal(childUsers[6].level, 8, 'fail level at user:' + 6);
    assert.equal(childUsers[7].level, 9, 'fail level at user:' + 7);

    assert.equal(childUsers[0].rank, 9, 'fail rank at user:' + 0);
    assert.equal(childUsers[1].rank, 9, 'fail rank at user:' + 1);
    assert.equal(childUsers[2].rank, 9, 'fail rank at user:' + 2);
    assert.equal(childUsers[3].rank, 9, 'fail rank at user:' + 3);
    assert.equal(childUsers[4].rank, 7, 'fail rank at user:' + 4);
    assert.equal(childUsers[5].rank, 7, 'fail rank at user:' + 5);
    assert.equal(childUsers[6].rank, 5, 'fail rank at user:' + 6);
    assert.equal(childUsers[7].rank, 5, 'fail rank at user:' + 7);

    assert.equal(childUsers[6].rank1Received, 81, 'fail rank1Received at user:' + 6);
    assert.equal(childUsers[7].rank1Received, 0, 'fail rank1Received at user:' + 6);
  });

  it('init the user at level10 - should fail(初始化第十层用户 - 应该失败)', async function() {
    try {
      await org.initUser(accounts[9], accounts[10]);
      const childUser = await onchainUser(level2user1);
      assert.fail('Expected throw not received,childUser:' + childUser);
    } catch (error) {
      assert.equal(error.reason, 'Wrong level', 'Expected not correct');
    }
  });

  it('register user(注册新用户)', async function() {
    const newUserAddr = accounts[10];
    const parentUserAddr = accounts[9];
    const aS = await signUpgrade(newUserAddr, newUserAddr, 1);
    const iS = await signUpgrade(parentUserAddr, newUserAddr, 1);
    await org.register(newUserAddr, parentUserAddr, [aS.v, iS.v, iS.v], [aS.r, iS.r, iS.r], [aS.s, iS.s, iS.s]);
    const newUser = await onchainUser(newUserAddr);
    assert.deepEqual(
      newUser,
      offchainUser({
        invitor: parentUserAddr,
        parent: parentUserAddr,
        self: newUserAddr,
        rank: 1,
        level: 10,
      }),
      'incorrect new user!'
    );
    const a9Balance = await mht.balanceOf(accounts[9]);
    assert.equal(a9Balance, web3.utils.toWei('40', 'ether'), 'wrong balance' + a9Balance);
  });

  it('upgrade rank1 user with 1 child - should fail(升级只有一个下层的一星用户 - 应该失败)', async function() {
    const target = accounts[10];
    const approver = accounts[8];
    const tS = await signUpgrade(target, target, 2);
    const aS = await signUpgrade(approver, target, 2);
    try {
      await org.lowRankUpgrade(target, [tS.v, aS.v], [tS.r, aS.r], [tS.s, aS.s]);
      assert.fail('Expected throw not received,childUser:' + target);
    } catch (error) {
      assert.equal(error.reason, 'Upgrade Check failed', 'Expected not correct');
    }
  });

  it('batch register for 30 users(批量注册30个用户)', async function() {
    const invitor = accounts[10];
    const applicants = accounts.slice(11, 41);
    const invitors = Array(30).fill(invitor);
    const vArray = [];
    const rArray = [];
    const sArray = [];
    const officer = await org.getManager.call('0x0000000000000000000000000000000000000000', invitor, 1);
    for (let index = 0; index < applicants.length; index++) {
      const aS = await signUpgrade(applicants[index], applicants[index], 1);
      const iS = await signUpgrade(invitor, applicants[index], 1);
      const oS = await signUpgrade(officer, applicants[index], 1);
      vArray.push([aS.v, iS.v, oS.v]);
      rArray.push([aS.r, iS.r, oS.r]);
      sArray.push([aS.s, iS.s, oS.s]);
    }
    await org.batchUpdate(applicants, invitors, vArray, rArray, sArray, ...Array(8).fill([]));
    for (let index = 0; index < applicants.length; index++) {
      const applicantUser = await onchainUser(applicants[index]);
      assert.deepEqual(
        applicantUser,
        offchainUser({
          children: applicantUser.children,
          invitor,
          parent:
            index >= 12
              ? applicants[3 + 9 * Math.floor((index - 12) / 9) + 3 * (index % 3)]
              : index >= 3
              ? applicants[index % 3]
              : invitor,
          self: applicants[index],
          rank: 1,
          level: index >= 12 ? 13 + Math.floor((index - 12) / 9) : index >= 3 ? 12 : 11,
        }),
        index
      );
    }
  });

  it('upgrade rank1 -> rank3 user(升级1->3)', async function() {
    const target = accounts[10];
    const approverForR2 = accounts[8];
    const approverForR3 = accounts[7];
    const tS2 = await signUpgrade(target, target, 2);
    const aS2 = await signUpgrade(approverForR2, target, 2);
    const tS3 = await signUpgrade(target, target, 3);
    const aS3 = await signUpgrade(approverForR3, target, 3);
    await org.lowRankUpgrade(target, [tS2.v, aS2.v], [tS2.r, aS2.r], [tS2.s, aS2.s]);
    await org.lowRankUpgrade(target, [tS3.v, aS3.v], [tS3.r, aS3.r], [tS3.s, aS3.s]);
    const targetUser = await onchainUser(target);
    assert.equal(targetUser.rank, 3, 'rank change fail');
  });

  it('upgrade, rank3 -> rank4(升级3->4)', async function() {
    const target = accounts[10];
    const approver = accounts[6];
    const tS = await signUpgrade(target, target, 4);
    const aS = await signUpgrade(approver, target, 4);
    await org.lowRankUpgrade(target, [tS.v, aS.v], [tS.r, aS.r], [tS.s, aS.s]);
    const targetUser = await onchainUser(target);
    assert.equal(targetUser.rank, 4, 'rank change fail');
  });

  it('batch upgrade, rank4 -> rank8(批量升级4->8)', async function() {
    const targets = Array(4).fill(accounts[10]);
    const approvers = [accounts[5], accounts[4], accounts[3], accounts[2]];
    const officers = [accounts[3], accounts[3], accounts[1], accounts[1]];
    let vArray = [];
    let rArray = [];
    let sArray = [];
    for (let index = 0; index < targets.length; index++) {
      const tS = await signUpgrade(targets[index], targets[index], 5 + index);
      const aS = await signUpgrade(approvers[index], targets[index], 5 + index);
      const oS = await signUpgrade(officers[index], targets[index], 5 + index);
      vArray.push([tS.v, aS.v, oS.v]);
      rArray.push([tS.r, aS.r, oS.r]);
      sArray.push([tS.s, aS.s, oS.s]);
    }
    await org.batchUpdate(...Array(9).fill([]), targets, vArray, rArray, sArray);
    const targetUser = await onchainUser(targets[0]);
    assert.equal(targetUser.rank, 8, 'rank change fail');
  });

  it('top rank pre-upgrade(9星预升级)', async function() {
    const target = accounts[10];
    const approver = accounts[1];
    const tS = await signUpgrade(target, target, 9);
    const aS = await signUpgrade(approver, target, 9);
    await org.topRankPreUpgrade(target, [tS.v, aS.v], [tS.r, aS.r], [tS.s, aS.s]);
    const topRankPermission = await org.topRankPermissionMap(target);
    assert.equal(topRankPermission, 1, 'set top rank permission fail');
  });

  it('top rank upgrade(9星升级)', async function() {
    const target = accounts[10];
    const applicants = accounts.slice(41, 44);
    const invitors = Array(30).fill(target);
    let vArray = [];
    let rArray = [];
    let sArray = [];
    const officer = await org.getManager.call(target, accounts[9], 1);
    for (let index = 0; index < applicants.length; index++) {
      const aS = await signUpgrade(applicants[index], applicants[index], 1);
      const iS = await signUpgrade(target, applicants[index], 1);
      const oS = await signUpgrade(officer, applicants[index], 1);
      vArray.push([aS.v, iS.v, oS.v]);
      rArray.push([aS.r, iS.r, oS.r]);
      sArray.push([aS.s, iS.s, oS.s]);
    }
    await org.batchUpdate(applicants, invitors, vArray, rArray, sArray, ...Array(8).fill([]));
    const targetUser = await onchainUser(target);
    assert.equal(targetUser.rank, 9, 'upgrade fail');
  });

  it('buyer complain higher(买家投诉卖家)', async function() {
    caseBuyer = accounts[13];
    caseSeller = await org.getApprover(caseBuyer, 2);
    caseArbiter = accounts[97];
    const sellerSig = await signTrade(caseSeller, caseBuyer, caseSeller, 2);
    const cSig = await signPunishment(caseBuyer, caseSeller, 3);
    const aSig = await signPunishment(caseArbiter, caseSeller, 3);
    await org.punishSeller(caseBuyer, caseArbiter, caseSeller, cSig, aSig, 2, sellerSig, 3, true);
    const caseSellerUser = await onchainUser(caseSeller);
    const approval = await org.judgedApproval(caseBuyer, caseSeller);

    assert.equal(caseSellerUser.frozen, true, 'freeze fail');
    assert.equal(approval, true, 'approval fail');
  });

  it('upgrade after complaint(投诉后的免签名升级)', async function() {
    const target = accounts[13];
    const tS = await signUpgrade(target, target, 2);
    await org.lowRankUpgrade(target, [tS.v, tS.v], [tS.r, tS.r], [tS.s, tS.s]);
    const targetUser = await onchainUser(target);
    assert.equal(targetUser.rank, 2, 'rank change fail');
  });

  it('delegated transfer token for comittees(代转发token创建委员会)', async function() {
    const origin = accounts[0];
    const marketing = accounts[99];
    const committees = accounts.slice(1, 6);
    const expectedBalances = [
      web3.utils.toWei('10080', 'ether'),
      web3.utils.toWei('10020', 'ether'),
      web3.utils.toWei('10060', 'ether'),
      web3.utils.toWei('10020', 'ether'),
      web3.utils.toWei('10020', 'ether'),
    ];
    for (let index = 0; index < committees.length; index++) {
      const sig = await signTx(
        marketing,
        committees[index],
        web3.utils.toWei('10000', 'ether'),
        web3.utils.toWei('5', 'ether'),
        index
      );
      await mht.delegatedTransfer(
        sig,
        committees[index],
        web3.utils.toWei('10000', 'ether'),
        web3.utils.toWei('5', 'ether'),
        index
      );
      const balance = await mht.balanceOf(committees[index]);
      assert.equal(String(balance), expectedBalances[index], 'delegated error' + index);
    }
    const mBalance = await mht.balanceOf(marketing);
    const oBalance = await mht.balanceOf(accounts[0]);
    assert.equal(mBalance, web3.utils.toWei('99949975', 'ether'), 'delegated error' + marketing);
    assert.equal(oBalance, web3.utils.toWei('25', 'ether'), 'delegated error' + origin);
  });

  it('freeze arbiter,downgrade buyer and freeze 7 days,unfreeze seller - review by committees(冻结审核员，降级并冻结买家7日，解冻卖家)', async function() {
    const vArray = [];
    const rArray = [];
    const sArray = [];
    const committees = accounts.slice(1, 6);
    for (let index = 0; index < committees.length; index++) {
      const sigObj = await signReview(committees[index], caseBuyer, caseSeller, 0, false, true, [1, 0, 3]);
      vArray.push(sigObj.v);
      rArray.push(sigObj.r);
      sArray.push(sigObj.s);
    }
    await org.committeeReview(caseBuyer, caseSeller, 2, false, true, [1, 0, 3], vArray, rArray, sArray);

    const caseBuyerUser = await onchainUser(caseBuyer);
    const caseSellerUser = await onchainUser(caseSeller);
    const caseArbiterUser = await onchainUser(caseArbiter);
    assert.equal(caseBuyerUser.rank, 1, 'downgrade fail');
    assert.isAbove(caseBuyerUser.releaseAt, Date.now() / 1000, 'downgrade fail');
    assert.equal(caseArbiterUser.frozen, true, 'freeze caseArbiter fail');
    assert.equal(caseSellerUser.frozen, false, 'unfreeze caseSeller fail');
  });

  // utils

  async function signUpgrade(signer, applicant, targetRank) {
    const bytes = await org.upgradeHashBuild.call(applicant, targetRank);
    const sig = await web3.eth.sign(bytes, signer);
    return {
      v: '0x' + sig.slice(130, 132),
      r: sig.slice(0, 66),
      s: '0x' + sig.slice(66, 130),
    };
  }

  async function signPunishment(signer, target, type) {
    const bytes = await org.punishmentHashBuild(target, type);
    return await web3.eth.sign(bytes, signer);
  }

  async function signTrade(signer, buyer, seller, rank) {
    const bytes = await org.tradeHashBuild(buyer, seller, rank);
    return await web3.eth.sign(bytes, signer);
  }

  async function signReview(signer, buyer, seller, tradeNonce, shouldUpgrade, shouldDowngrade, types) {
    const bytes = await org.reviewHashBuild(buyer, seller, tradeNonce, shouldUpgrade, shouldDowngrade, types);
    const sig = await web3.eth.sign(bytes, signer);
    return {
      v: '0x' + sig.slice(130, 132),
      r: sig.slice(0, 66),
      s: '0x' + sig.slice(66, 130),
    };
  }

  async function signTx(signer, to, tokens, fee, nonce) {
    const bytes = await mht.delegatedTxHashBuild(to, tokens, fee, nonce);
    return await web3.eth.sign(bytes, signer);
  }

  function offchainUser(user) {
    return Object.assign({}, userModel, user);
  }

  async function onchainUser(userAddr) {
    const userMainPart = await org.userMap(userAddr);
    const userChildren = await org.getChildren(userAddr);
    return {
      children: userChildren,
      parent: userMainPart.parent,
      self: userMainPart.self,
      invitor: userMainPart.invitor,
      rank: Number(userMainPart.rank),
      level: Number(userMainPart.level),
      frozen: userMainPart.frozen,
      releaseAt: Number(userMainPart.releaseAt),
      rank1Received: Number(userMainPart.rank1Received),
      rank1Delivered: Number(userMainPart.rank1Delivered),
    };
  }
});
