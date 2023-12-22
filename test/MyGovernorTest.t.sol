// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "../lib/forge-std/src/Test.sol";

import {Box} from "../src/Box.sol";
import {MyGovernor} from "../src/MyGovernor.sol";
import {TimeLock} from "../src/TimeLock.sol";
import {VotingToken} from "../src/VotingToken.sol";

contract MyGovernorTest is Test {
    VotingToken votingToken;
    Box box;
    MyGovernor governor;
    TimeLock timelock;

    address public USER = makeAddr("USER");
    uint256 public constant INITIAL_SUPPLY = 100 ether;

    address[] proposers;
    address[] executors;
    uint256[] values;
    bytes[] calldatas;
    address[] targets;

    uint256 public constant MIN_DELAY = 3600; // 1 hour -> after a vote passes
    // ! MyGovernor.sol -> in constructor it is set up to 7200
    uint256 public constant VOTING_DELAY = 7200; // how many blocks till the vote is active
    uint256 public constant VOTING_PERIOD = 50400;

    function setUp() public {
        votingToken = new VotingToken();
        votingToken.mint(USER, INITIAL_SUPPLY);

        vm.startPrank(USER);
        votingToken.delegate(USER);
        timelock = new TimeLock(MIN_DELAY, proposers, executors);
        governor = new MyGovernor(votingToken, timelock);

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(0));
        timelock.revokeRole(adminRole, USER);
        vm.stopPrank();

        box = new Box();
        box.transferOwnership(address(timelock));
    }

    function testCantUpdateBoxWithoutGovernance() public {
        vm.expectRevert();
        box.store(111);
    }

    function testGovernanceUpdatesBox() public {
        uint256 valueToStore = 1111;
        string memory description = "store 1111 in box";
        bytes memory encodedFunctionCall = abi.encodeWithSignature("store(uint256)", valueToStore);
        values.push(0);
        calldatas.push(encodedFunctionCall);
        targets.push(address(box));

        // 1. Propose to the DAO
        uint256 proposalId = governor.propose(targets, values, calldatas, description);
        // ! Can check values for state in IGovernor.sol
        console.log("Proposal state -> ", uint256(governor.state(proposalId)));

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.roll(block.number + VOTING_DELAY + 1);
        console.log("Proposal state -> ", uint256(governor.state(proposalId)));

        // 2. Vote
        string memory reason = "because i can";
        // ! In GovernorCountingSimple.sol -> 0-Against, 1-For, 2-Abstain
        uint8 voteWay = 1; // voting FOR

        vm.prank(USER);
        governor.castVoteWithReason(proposalId, voteWay, reason);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        vm.roll(block.number + VOTING_PERIOD + 1);

        console.log("Proposal state -> ", uint256(governor.state(proposalId)));

        // 3. Queue the TX
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));
        governor.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.roll(block.number + MIN_DELAY + 1);
        console.log("Proposal state -> ", uint256(governor.state(proposalId)));

        // 4. Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        console.log("Box value -> ", box.getNumber());
        assert(box.getNumber() == valueToStore);
    }
}
