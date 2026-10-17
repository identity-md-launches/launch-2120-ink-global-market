// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InkToken} from "../src/InkToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase} from "./helpers/TestBase.sol";

/// @dev Drives both valid and invalid calls in random order. Invalid calls are caught, checked to
/// revert with the expected ERC-6093 error, and must leave the model untouched. Recipients include
/// the token contract itself, where tokens can arrive but never leave.
contract InkTokenFailurePathHandler is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    InkToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public ghostMoved;
    uint256 public ghostExpectedReverts;
    uint256 public ghostUnexpectedSuccesses;
    uint256 public ghostWrongErrors;

    constructor() {
        token = new InkToken();
        actors = [address(this), address(0xA11CE), address(0xB0B), address(0xCA401), address(token)];
        expectedBalance[address(this)] = SUPPLY;
    }

    function actorCount() external pure returns (uint256) {
        return 5;
    }

    /// @dev The token contract can receive but never sends or approves.
    function _sender(uint256 seed) internal view returns (address) {
        return actors[seed % 4];
    }

    function _any(uint256 seed) internal view returns (address) {
        return actors[seed % 5];
    }

    function _expectError(bytes memory err, bytes memory expected) internal {
        ghostExpectedReverts++;
        if (keccak256(err) != keccak256(expected)) ghostWrongErrors++;
    }

    // ---------------------------------------------------------------- valid calls

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) public {
        address from = _sender(fromSeed);
        address to = _any(toSeed);
        uint256 amount = rawAmount % (expectedBalance[from] + 1);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ghostMoved += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) public {
        address owner = _sender(ownerSeed);
        address spender = _any(spenderSeed);
        uint256 mode = rawAmount % 4;
        uint256 amount =
            mode == 0 ? 0 : mode == 1 ? rawAmount % (SUPPLY + 1) : mode == 2 ? rawAmount : type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) public {
        address owner = _sender(ownerSeed);
        address spender = _sender(spenderSeed);
        address to = _any(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = rawAmount % (limit + 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        ghostMoved += amount;
    }

    // ---------------------------------------------------------------- invalid calls

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 rawExcess) public {
        address from = _sender(fromSeed);
        address to = _any(toSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = held + 1 + rawExcess % (type(uint256).max - held);
        vm.prank(from);
        try token.transfer(to, amount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(
                err, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
            );
        }
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) public {
        address from = _sender(fromSeed);
        vm.prank(from);
        try token.transfer(address(0), rawAmount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(err, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 rawAmount) public {
        address owner = _sender(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), rawAmount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(err, abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        }
    }

    function transferFromOverAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawExcess)
        public
    {
        address owner = _sender(ownerSeed);
        address spender = _sender(spenderSeed);
        address to = _any(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed == type(uint256).max) {
            // Unlimited allowance cannot be exceeded; revoke it through the token so the model stays in step.
            vm.prank(owner);
            token.approve(spender, 0);
            expectedAllowance[owner][spender] = 0;
            allowed = 0;
        }
        uint256 amount = allowed + 1 + rawExcess % (type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(
                err, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
        }
    }

    function transferFromOverBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawExcess) public {
        address owner = _sender(ownerSeed);
        address spender = _sender(spenderSeed);
        address to = _any(toSeed);
        uint256 held = expectedBalance[owner];
        if (held == SUPPLY) return; // nothing can exceed the whole supply within an allowance below max
        uint256 amount = held + 1 + rawExcess % (SUPPLY - held);
        // Grant exactly enough allowance, so the only reason to fail is the balance.
        vm.prank(owner);
        token.approve(spender, amount);
        expectedAllowance[owner][spender] = amount;
        vm.prank(spender);
        try token.transferFrom(owner, to, amount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(
                err, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount)
            );
        }
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) public {
        address owner = _sender(ownerSeed);
        address spender = _sender(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner] < allowed ? expectedBalance[owner] : allowed;
        uint256 amount = rawAmount % (limit + 1);
        vm.prank(spender);
        try token.transferFrom(owner, address(0), amount) {
            ghostUnexpectedSuccesses++;
        } catch (bytes memory err) {
            _expectError(err, abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        }
    }

    function unknownCall(uint256 callerSeed, bytes4 selector, bytes calldata args) public {
        if (
            selector == bytes4(keccak256("name()")) || selector == bytes4(keccak256("symbol()"))
                || selector == bytes4(keccak256("decimals()")) || selector == bytes4(keccak256("totalSupply()"))
                || selector == bytes4(keccak256("balanceOf(address)"))
                || selector == bytes4(keccak256("transfer(address,uint256)"))
                || selector == bytes4(keccak256("allowance(address,address)"))
                || selector == bytes4(keccak256("approve(address,uint256)"))
                || selector == bytes4(keccak256("transferFrom(address,address,uint256)"))
                || selector == bytes4(keccak256("INITIAL_SUPPLY()"))
        ) return;
        vm.prank(_sender(callerSeed));
        (bool ok,) = address(token).call(abi.encodePacked(selector, args));
        if (ok) ghostUnexpectedSuccesses++;
        else ghostExpectedReverts++;
    }
}

contract InkTokenFailurePathInvariantTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InkTokenFailurePathHandler internal handler;
    InkToken internal token;

    function setUp() public {
        handler = new InkTokenFailurePathHandler();
        token = handler.token();
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_modelMatchesAndSupplyIsFixed() public view {
        uint256 n = handler.actorCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            address holder = handler.actors(i);
            uint256 balance = token.balanceOf(holder);
            assertEq(balance, handler.expectedBalance(holder));
            sum += balance;
            for (uint256 j; j < n; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(holder, spender), handler.expectedAllowance(holder, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_invalidCallsNeverSucceed() public view {
        assertEq(handler.ghostUnexpectedSuccesses(), 0);
        assertEq(handler.ghostWrongErrors(), 0);
    }

    /// @dev Guards against a vacuous campaign: every sequence must have driven some invalid calls.
    function afterInvariant() public view {
        assertTrue(handler.ghostExpectedReverts() > 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_tokenContractNeverSpendsOrApproves() public view {
        // Nothing can move the token contract's own balance out, so it only ever grows.
        assertEq(token.balanceOf(address(token)), handler.expectedBalance(address(token)));
        for (uint256 j; j < handler.actorCount(); ++j) {
            assertEq(token.allowance(address(token), handler.actors(j)), 0);
        }
    }
}
