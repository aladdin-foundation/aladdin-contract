// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AladdinToken is ERC20, Ownable {
    constructor(address owner_) ERC20("Aladdin Token", "Al") Ownable(owner_) {
        _mint(owner_, 100000000 ether);
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
