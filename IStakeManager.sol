pragma solidity>0.8.0;//SPDX-License-Identifier:None

interface IStakeManager {
    event Deposited(address,uint);
    event Withdrawn(address,address,uint);
    event StakeLocked(address,uint,uint);
    event StakeUnlocked(address,uint);
    event StakeWithdrawn(address,address,uint);
    struct DepositInfo{uint112 deposit;bool staked;uint112 stake;uint32 unstakeDelaySec;uint48 withdrawTime;}
    struct StakeInfo {uint stake;uint unstakeDelaySec;}
    function getDepositInfo(address)external view returns(DepositInfo memory);
    function balanceOf(address)external view returns(uint);
    function depositTo(address)external payable;
    function addStake(uint32)external payable;
    function unlockStake()external;
    function withdrawStake(address payable)external;
    function withdrawTo(address payable,uint) external;
}