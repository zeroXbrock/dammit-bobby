// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor(
        string memory tokenLetter
    )
        ERC20(
            string(abi.encodePacked("TKN", tokenLetter)),
            string(abi.encodePacked("Token", tokenLetter))
        )
    {
        _mint(msg.sender, 100 ether);
    }
}
