// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Local fixture only, not Sogdia's launch token. One constructor mint, no public mint.
contract TestToken is ERC20 {
    constructor(uint256 supply) ERC20("Local reward fixture", "TEST") {
        _mint(msg.sender, supply);
    }
}
