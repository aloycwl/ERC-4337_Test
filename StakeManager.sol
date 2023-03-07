pragma solidity>0.8.0;//SPDX-License-Identifier:None

import "IStakeManager.sol";

abstract contract StakeManager is IStakeManager{
    mapping(address=>DepositInfo)public deposits;
    function getDepositInfo(address account)public view returns(DepositInfo memory){
        return deposits[account];
    }
    function _getStakeInfo(address addr)internal view returns(StakeInfo memory info) {
        DepositInfo storage depositInfo=deposits[addr];
        (info.stake,info.unstakeDelaySec)=(depositInfo.stake,depositInfo.unstakeDelaySec);
    }
    function balanceOf(address account)public view returns(uint){
        return deposits[account].deposit;
    }
    receive() external payable{
        depositTo(msg.sender);
    }
    function _incrementDeposit(address account,uint amount)internal{
        DepositInfo storage info=deposits[account];
        uint newAmount=info.deposit+amount;
        //require(newAmount<=type(uint112).max);
        info.deposit=uint112(newAmount);
    }
    function depositTo(address account)public payable{
        _incrementDeposit(account,msg.value);
    }
    function addStake(uint32 unstakeDelaySec)public payable{
        DepositInfo storage info=deposits[msg.sender];
        //require(unstakeDelaySec>0&&unstakeDelaySec>=info.unstakeDelaySec);
        uint stake=info.stake+msg.value;
        //require(stake>0&&stake<=type(uint112).max);
        deposits[msg.sender]=DepositInfo(info.deposit,true,uint112(stake),unstakeDelaySec,0);
    }
    function unlockStake()external{
        DepositInfo storage info=deposits[msg.sender];
        //require(info.unstakeDelaySec!=0&&info.staked);
        (info.withdrawTime,info.staked)=(uint48(block.timestamp)+info.unstakeDelaySec,false);
    }
    function withdrawStake(address payable withdrawAddress)external{
        DepositInfo storage info=deposits[msg.sender];
        uint stake=info.stake;
        //require(stake>0&&info.withdrawTime>0&&info.withdrawTime<=block.timestamp);
        (info.unstakeDelaySec,info.withdrawTime,info.stake)=(0,0,0);
        (bool success,)=withdrawAddress.call{value:stake}("");
        require(success);
    }
    function withdrawTo(address payable withdrawAddress,uint withdrawAmount)external{
        DepositInfo storage info=deposits[msg.sender];
        //require(withdrawAmount<=info.deposit);
        info.deposit=uint112(info.deposit-withdrawAmount);
        (bool success,)=withdrawAddress.call{value:withdrawAmount}("");
        require(success);
    }
}