pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract HelperWithTokens {

    function withdrawTokens(address _token) public {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        (bool success) = IERC20(_token).transfer(msg.sender, amount);
        require(success, "error");
    }

    function giveApprove(address _to, uint256 _amount, address _token) public {
        (bool success) = IERC20(_token).approve(_to, _amount);
    }

}