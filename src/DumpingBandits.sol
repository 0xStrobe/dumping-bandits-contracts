// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IRandomness} from "./interfaces/IRandomness.sol";

error NOT_OWNER();
error WRONG_PRICE();
error ROUND_FULL();

contract DumpingBandits is ERC721, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    address public owner;
    IRandomness public randomness;

    constructor(address _randomness) ERC721("Dumping Bandits", "BANDIT") {
        owner = msg.sender;
        randomness = IRandomness(_randomness);
    }

    uint256 public roundId = 0;
    uint256 public participantsPerRound = 100;
    uint256 public price = 10 ether;

    event RandomnessSet(address randomness);
    event OwnerSet(address owner);

    event RoundStarted(uint256 indexed roundId, uint256 participantsPerRound);
    event RoundEnded(uint256 indexed roundId, uint256 randomness);
    event ParticipantAdded(uint256 indexed roundId, address participant);

    mapping(uint256 => mapping(address => bool)) public rounds;
    uint256 public totalParticipants = 0;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function tokenURI(uint256 id) public pure override returns (string memory) {
        return string(abi.encodePacked("https://dumpingbandits.canto.life/nft/", Strings.toString(id)));
    }

    function setRandomness(address _randomness) public onlyOwner {
        randomness = IRandomness(_randomness);
        emit RandomnessSet(_randomness);
    }

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
        emit OwnerSet(_owner);
    }

    function participate() public payable nonReentrant {
        if (msg.value != price) revert WRONG_PRICE();
        if (totalParticipants >= participantsPerRound) revert ROUND_FULL();

        // add participant to the current round
        rounds[roundId][msg.sender] = true;
        unchecked {
            totalParticipants++;
        }

        emit ParticipantAdded(roundId, msg.sender);

        // if the round is full, start a new one
        if (totalParticipants == participantsPerRound) {
            _endRound();
        }
    }

    function _startRound() internal {
        roundId++;
        totalParticipants = 0;
        emit RoundStarted(roundId, participantsPerRound);
    }

    function _endRound() internal {
        // TODO: distribute or make claimable the prize
        // TODO: also burn the gas token
        // emit RoundEnded(roundId, randomness);
    }

    /// @dev Derives a winner from a random number, round id, total participants, and weight (wad) of this winner.
    /// @dev If we want to skip a winner (eg. the second place is the same as the first place), we can use the _skips parameter.
    /// @param _totalParticipants The total number of participants in the round.
    /// @param _weight The weight of the winner (if deriving a prize with 30% chance, the weight is 0.3 ether).
    /// @param _randomness The random number to derive the winner from.
    /// @param _skips The number of potential winners to skip before picking the actual winner.
    function _deriveWinner(uint256 _totalParticipants, uint256 _weight, uint256 _randomness, uint256 _skips)
        internal
        view
        returns (uint256)
    {
        // TODO: implement
    }
}
