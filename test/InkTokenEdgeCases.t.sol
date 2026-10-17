// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {InkToken} from "../src/InkToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {TestBase, Vm} from "./helpers/TestBase.sol";

/// @dev Test-only factory that deploys through CREATE2, as a launch factory does.
contract Create2FactoryFixture {
    function deploy(bytes32 salt) external returns (InkToken) {
        return new InkToken{salt: salt}();
    }

    function predict(bytes32 salt) external view returns (address) {
        bytes32 codeHash = keccak256(type(InkToken).creationCode);
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, codeHash)))));
    }

    function forward(InkToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

/// @dev Boundary values and failure paths the main suite does not pin.
contract InkTokenEdgeCasesTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    InkToken internal token;

    function setUp() public {
        token = new InkToken();
    }

    // ---------------------------------------------------------------- supply and metadata

    function test_supplyIsExactlyTenToTheTwentySeventh() public view {
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.totalSupply() / 10 ** token.decimals(), 1_000_000_000);
        assertEq(token.totalSupply() % 10 ** token.decimals(), 0);
    }

    function test_create2DeploymentMintsToFactoryAtPredictedAddress() public {
        Create2FactoryFixture factory = new Create2FactoryFixture();
        bytes32 salt = bytes32(uint256(42));
        address predicted = factory.predict(salt);
        InkToken deployed = factory.deploy(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(tx.origin), 0);
    }

    function test_create2RedeploymentWithSameSaltReverts() public {
        Create2FactoryFixture factory = new Create2FactoryFixture();
        factory.deploy(bytes32(uint256(7)));
        vm.expectRevert();
        factory.deploy(bytes32(uint256(7)));
    }

    function test_separateDeploymentsHaveIndependentSupplies() public {
        Create2FactoryFixture factory = new Create2FactoryFixture();
        InkToken first = factory.deploy(bytes32(uint256(1)));
        InkToken second = factory.deploy(bytes32(uint256(2)));
        factory.forward(first, ALICE, SUPPLY);
        assertEq(first.balanceOf(ALICE), SUPPLY);
        assertEq(second.balanceOf(ALICE), 0);
        assertEq(second.balanceOf(address(factory)), SUPPLY);
        assertEq(first.totalSupply(), SUPPLY);
        assertEq(second.totalSupply(), SUPPLY);
    }

    /// @dev The ten percent swarm share, the 80% pool share and the remainder all move exactly.
    function test_launchSplitByBasisPointsIsExact() public {
        Create2FactoryFixture factory = new Create2FactoryFixture();
        InkToken deployed = factory.deploy(bytes32(uint256(3)));
        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_000 / 10_000;
        factory.forward(deployed, ALICE, swarm);
        factory.forward(deployed, BOB, pool);
        uint256 remainder = deployed.balanceOf(address(factory));
        assertEq(remainder, SUPPLY - swarm - pool);
        factory.forward(deployed, SPENDER, remainder);
        assertEq(deployed.balanceOf(ALICE), swarm);
        assertEq(deployed.balanceOf(BOB), pool);
        assertEq(deployed.balanceOf(SPENDER), remainder);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- zero-address paths

    function test_transferFromZeroAddressRevertsWithInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_approveFromZeroAddressRevertsWithInvalidApprover() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(SPENDER, 1);
        assertEq(token.allowance(address(0), SPENDER), 0);
    }

    function test_transferFromZeroOwnerRevertsWithInvalidApprover() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 0);
    }

    function test_transferFromZeroOwnerPositiveAmountRevertsWithInsufficientAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(0), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approveZeroSpenderRevertsForAnyAmount(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), amount);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testFuzz_transferToZeroRevertsForAnyAmount(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- boundaries

    function test_transferMaxUintRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(ALICE, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferOneWeiMoreThanBalanceReverts() public {
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1 ether, 1 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether + 1);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1 ether));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 1 ether);
    }

    function test_allowanceJustBelowMaxIsFiniteAndDecreases() public {
        uint256 almost = type(uint256).max - 1;
        token.approve(SPENDER, almost);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), almost - 1);
    }

    function test_allowanceJustBelowMaxStillCapsSpending() public {
        uint256 almost = type(uint256).max - 1;
        token.approve(SPENDER, almost);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, almost, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), almost);
    }

    function test_unlimitedAllowanceStillBoundedByBalance() public {
        token.transfer(ALICE, 5 ether);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5 ether, 5 ether + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 5 ether + 1);
        assertEq(token.balanceOf(ALICE), 5 ether);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
    }

    function test_selfApprovalAllowsSelfTransferFrom() public {
        token.approve(address(this), 3 ether);
        assertTrue(token.transferFrom(address(this), ALICE, 3 ether));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(ALICE), 3 ether);
    }

    function test_allowanceIsPerOwnerAndPerSpender() public {
        token.transfer(ALICE, 10 ether);
        token.approve(SPENDER, 4 ether);
        // Allowance from this contract does not let SPENDER move ALICE's balance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, SPENDER, 1);
        // And BOB cannot use SPENDER's allowance.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), SPENDER), 4 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_transferFromSecondSpendOfExhaustedAllowanceReverts() public {
        token.approve(SPENDER, 2 ether);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 2 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 2 ether);
    }

    /// @dev Tokens sent to the token contract are accounted for but nobody can move them back out.
    function test_tokensSentToTokenContractAreHeldButSupplyUnchanged() public {
        token.transfer(address(token), 9 ether);
        assertEq(token.balanceOf(address(token)), 9 ether);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(token), address(this), 1);
        assertEq(token.balanceOf(address(token)), 9 ether);
    }

    // ---------------------------------------------------------------- events

    function test_transferFromEmitsOnlyTransferNoApproval() public {
        token.approve(SPENDER, 10 ether);
        vm.recordLogs();
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 4 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(address(this)))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(ALICE))));
        assertEq(abi.decode(logs[0].data, (uint256)), 4 ether);
    }

    function test_failedCallsEmitNothing() public {
        vm.recordLogs();
        vm.prank(ALICE);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (BOB, 1)));
        assertTrue(!ok);
        (ok,) = address(token).call(abi.encodeCall(token.approve, (address(0), 1)));
        assertTrue(!ok);
        vm.prank(SPENDER);
        (ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(this), ALICE, 1)));
        assertTrue(!ok);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    // ---------------------------------------------------------------- unknown entry points

    function _isKnownSelector(bytes4 selector) internal pure returns (bool) {
        return selector == bytes4(keccak256("name()")) || selector == bytes4(keccak256("symbol()"))
            || selector == bytes4(keccak256("decimals()")) || selector == bytes4(keccak256("totalSupply()"))
            || selector == bytes4(keccak256("balanceOf(address)"))
            || selector == bytes4(keccak256("transfer(address,uint256)"))
            || selector == bytes4(keccak256("allowance(address,address)"))
            || selector == bytes4(keccak256("approve(address,uint256)"))
            || selector == bytes4(keccak256("transferFrom(address,address,uint256)"))
            || selector == bytes4(keccak256("INITIAL_SUPPLY()"));
    }

    /// @dev Any selector outside the ERC-20 surface reverts and changes nothing, from any caller.
    function testFuzz_unknownSelectorsRevertAndChangeNothing(bytes4 selector, bytes memory args, bool asDeployer)
        public
    {
        while (_isKnownSelector(selector)) {
            selector = bytes4(keccak256(abi.encode(selector)));
        }
        token.transfer(ALICE, 1 ether);
        if (!asDeployer) vm.prank(BOB);
        (bool ok,) = address(token).call(abi.encodePacked(selector, args));
        assertTrue(!ok);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_fallbackCallsWithShortCalldataRevert() public {
        (bool ok,) = address(token).call(hex"");
        assertTrue(!ok);
        (ok,) = address(token).call(hex"a9");
        assertTrue(!ok);
        (ok,) = address(token).call(hex"a9059c");
        assertTrue(!ok);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    // ---------------------------------------------------------------- fuzzed properties

    function testFuzz_approveStoresAnyValueForAnySpender(address spender, uint256 amount) public {
        if (spender == address(0)) spender = SPENDER;
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(address(this), spender), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferBetweenHoldersRoundTrips(uint256 rawFirst, uint256 rawBack) public {
        uint256 first = rawFirst % (SUPPLY + 1);
        uint256 back = rawBack % (first + 1);
        token.transfer(ALICE, first);
        vm.prank(ALICE);
        token.transfer(address(this), back);
        assertEq(token.balanceOf(ALICE), first - back);
        assertEq(token.balanceOf(address(this)), SUPPLY - first + back);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_holderCannotOverspend(uint256 rawHeld, uint256 rawExcess) public {
        uint256 held = rawHeld % (SUPPLY + 1);
        uint256 amount = held + 1 + rawExcess % (type(uint256).max - held);
        token.transfer(ALICE, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, amount));
        vm.prank(ALICE);
        token.transfer(BOB, amount);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testFuzz_unlimitedAllowanceNeverDecreases(uint256 rawA, uint256 rawB) public {
        uint256 a = rawA % (SUPPLY / 2 + 1);
        uint256 b = rawB % (SUPPLY / 2 + 1);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, a);
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, b);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), a);
        assertEq(token.balanceOf(BOB), b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }

    function testFuzz_reapprovalOverwritesRegardlessOfPriorSpending(uint256 rawFirst, uint256 rawSpent, uint256 second)
        public
    {
        uint256 first = rawFirst % (SUPPLY + 1);
        uint256 spent = rawSpent % (first + 1);
        token.approve(SPENDER, first);
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, spent);
        token.approve(SPENDER, second);
        assertEq(token.allowance(address(this), SPENDER), second);
    }
}
