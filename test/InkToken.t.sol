// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InkToken} from "../src/InkToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, Vm} from "./helpers/TestBase.sol";

/// @dev Test-only factory/contract holder. No production configuration uses these fixtures.
contract TokenHolderFixture {
    function deploy() external returns (InkToken) {
        return new InkToken();
    }

    function forward(InkToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract InkTokenTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    InkToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new InkToken();
    }

    function test_metadataAndInitialSupply() public view {
        assertEq(token.name(), "Ink Global Market");
        assertEq(token.symbol(), "INK");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_constructorEmitsExactlyOneMintEvent() public {
        vm.recordLogs();
        InkToken deployed = new InkToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_factoryReceivesEntireSupply() public {
        TokenHolderFixture factory = new TokenHolderFixture();
        InkToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 37 ether);
        assertTrue(token.transfer(ALICE, 37 ether));
        assertEq(token.balanceOf(ALICE), 37 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 37 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferEntireSupply() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_approveEmitsEventAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 4 ether);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_emptyHolderCanApprove() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 15 ether));
        assertEq(token.allowance(ALICE, SPENDER), 15 ether);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_revokingAllowancePreventsSpending() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        assertTrue(token.approve(SPENDER, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_transferFromConsumesAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 6 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 4 ether);
        assertEq(token.balanceOf(ALICE), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 6 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 4 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSameHolderConsumesAllowanceOnly() public {
        token.approve(SPENDER, 11 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), 11 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteAllowanceIsNotDecreased() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10 ether));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 20 ether));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 20 ether);
    }

    function test_zeroTransferFromNeedsNoAllowanceOrBalance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyAccountCannotTransferPositiveAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_unapprovedSpenderCannotMoveTokens() public {
        token.transfer(ALICE, 10 ether);
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        // The deployer has no special right to spend another holder's balance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
    }

    function test_transferFromByHolderStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(ALICE);
        token.approve(SPENDER, 50 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 25 ether));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 25 ether);
        assertEq(token.allowance(ALICE, SPENDER), 50 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowance() public {
        token.approve(SPENDER, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSenderRevertsEvenForZeroAmount() public {
        vm.expectRevert();
        token.transferFrom(address(0), ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_launchDistributionAndContractTransfersAreExact() public {
        TokenHolderFixture factory = new TokenHolderFixture();
        TokenHolderFixture distributor = new TokenHolderFixture();
        TokenHolderFixture poolHolder = new TokenHolderFixture();
        InkToken deployed = factory.deploy();
        factory.forward(deployed, address(distributor), SUPPLY / 10);
        factory.forward(deployed, address(poolHolder), SUPPLY * 8 / 10);
        factory.forward(deployed, BOB, SUPPLY / 10);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(address(distributor)), SUPPLY / 10);
        assertEq(deployed.balanceOf(address(poolHolder)), SUPPLY * 8 / 10);
        assertEq(deployed.balanceOf(BOB), SUPPLY / 10);
        distributor.forward(deployed, ALICE, SUPPLY / 10);
        assertEq(deployed.balanceOf(address(distributor)), 0);
        assertEq(deployed.balanceOf(ALICE), SUPPLY / 10);
        poolHolder.forward(deployed, SPENDER, 17 ether);
        assertEq(deployed.balanceOf(SPENDER), 17 ether);
        vm.prank(SPENDER);
        assertTrue(deployed.transfer(address(poolHolder), 17 ether));
        assertEq(deployed.balanceOf(SPENDER), 0);
        assertEq(deployed.balanceOf(address(poolHolder)), SUPPLY * 8 / 10);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(ALICE, 25 ether);
        bytes[] memory calls = new bytes[](13);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("_mint(address,uint256)", BOB, 1 ether);
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether);
        calls[5] = abi.encodeWithSignature("pause()");
        calls[6] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[7] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[8] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("transferOwnership(address)", BOB);
        calls[10] = abi.encodeWithSignature("upgradeTo(address)", BOB);
        calls[11] = abi.encodeWithSignature("initialize(address)", BOB);
        calls[12] = abi.encodeWithSignature("setMinter(address)", BOB);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertTrue(!deployerSucceeded);
            vm.prank(BOB);
            (bool outsiderSucceeded,) = address(token).call(calls[i]);
            assertTrue(!outsiderSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 25 ether);
            assertEq(token.balanceOf(BOB), 0);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 25 ether));
        assertEq(token.balanceOf(BOB), 25 ether);
    }

    function test_plainEtherTransferIsRejected() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertTrue(!success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 rawAmount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_selfTransferPreservesBalance(uint256 rawAmount) public {
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 rawAllowance, uint256 rawAmount) public {
        uint256 allowance = rawAllowance % (SUPPLY + 1);
        uint256 amount = rawAmount % (allowance + 1);
        token.approve(SPENDER, allowance);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        assertEq(token.allowance(address(this), SPENDER), allowance - amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_exceedingAllowanceRevertsAtomically(uint256 rawAllowance) public {
        uint256 allowance = rawAllowance % SUPPLY;
        uint256 amount = allowance + 1;
        token.approve(SPENDER, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, allowance, amount)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.allowance(address(this), SPENDER), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testFuzz_exceedingBalanceRevertsAtomically(uint256 rawExcess) public {
        uint256 amount = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
