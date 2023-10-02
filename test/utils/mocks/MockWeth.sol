// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "@forge-std/Test.sol";
import {IERC20} from "@oz-v4.9.3/token/ERC20/IERC20.sol";
import {IWETH9} from "@uni-v3-periphery/interfaces/external/IWETH9.sol";

/// @title WETH9 adapted for solc v0.8, from horsefacts.eth
contract WETH9 is IWETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;

    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    fallback() external payable {
        deposit();
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) public {
        require(balanceOf[msg.sender] >= wad);
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}

/// @title MockWETH with mint, burn, and set functions
/// @dev Adjusts the amount of ETH held by the contract automagically
contract MockWeth is WETH9, Test {
    /// @dev Mints WETH to the given address & adjusts contract ETH balance
    /// @param to The address to mint to
    /// @param amount The amount to mint
    function mintTo(address to, uint256 amount) public {
        balanceOf[to] += amount;
        deal(address(this), address(this).balance + amount);
    }

    /// @dev Mints WETH to the sender & adjusts contract ETH balance
    /// @param amount The amount to mint
    function mint(uint256 amount) public {
        mintTo(msg.sender, amount);
    }

    /// @dev Burns WETH from the given address & adjusts contract ETH balance
    /// @param from The address to burn from
    /// @param amount The amount to burn
    function burn(address from, uint256 amount) public {
        balanceOf[from] -= amount;
        deal(address(this), address(this).balance - amount);
    }

    /// @dev Sets the WETH balance of the given address & adjusts contract ETH balance
    /// @param who The address to set the balance of
    /// @param amount The amount to set the balance to
    function set(address who, uint256 amount) public {
        int256 difference = int256(amount) - int256(balanceOf[who]);
        balanceOf[who] = amount;
        if (difference > 0) deal(address(this), uint256(int256(address(this).balance) + difference));
    }
}
