pragma solidity>0.8.0;//SPDX-License-Identifier:None

interface IStakeManager {
    event Deposited(address indexed,uint);
    event Withdrawn(address indexed,address,uint);
    event StakeLocked(address indexed,uint,uint);
    event StakeUnlocked(address indexed,uint);
    event StakeWithdrawn(address indexed,address,uint);
    struct DepositInfo{uint112 deposit;bool staked;uint112 stake;uint32 unstakeDelaySec;uint48 withdrawTime;}
    struct StakeInfo {uint stake;uint unstakeDelaySec;}
    function getDepositInfo(address account)external view returns(DepositInfo memory);
    function balanceOf(address account)external view returns(uint);
    function depositTo(address account)external payable;
    function addStake(uint32 _unstakeDelaySec)external payable;
    function unlockStake()external;
    function withdrawStake(address payable withdrawAddress)external;
    function withdrawTo(address payable withdrawAddress,uint withdrawAmount) external;
}