// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "solmate/utils/SafeTransferLib.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IRandomnessClient} from "./interfaces/IRandomnessClient.sol";

error NOT_OWNER();
error WRONG_PRICE();
error ZERO_WINNERS();
error ROUND_NOT_STARTED();
error ROUND_NOT_OVER();
error ZERO_ADDRESS();
error ALREADY_PARTICIPATED();

contract DumpingBandits is ERC721, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    address public owner;
    IRandomnessClient public rc;

    constructor(address _rc) ERC721("Dumping Bandits", "BANDIT") {
        if (_rc == address(0)) revert ZERO_ADDRESS();
        owner = msg.sender;
        rc = IRandomnessClient(_rc);
    }

    /*//////////////////////////////////////////////////////////////
                            DEFAULT RULES
    //////////////////////////////////////////////////////////////*/
    // uh yis indeed, dis can be modified by owner butta only applies to ze next round (current round issa not affected)
    uint256 public defaultPrice = 10 ether;
    uint256 public defaultMinDuration = 15 minutes;
    uint256 public defaultNoWinnerProbability = 0.00_0001 ether; // 0.0001%
    uint256[] public defaultPrizes = [0.4 ether, 0.25 ether, 0.15 ether]; // take home 40%, 25%, 15% of ze pot
    uint256 public defaultFinalizerReward = 10 ether;
    uint256 public defaultRedistributionReserve = 0.02 ether; // keep 2% of per round in contract for redistribution

    /*//////////////////////////////////////////////////////////////
                        GAME STATE N HISTORY
    //////////////////////////////////////////////////////////////*/
    struct Round {
        // game state
        uint256 roundStartedAt;
        uint256 totalParticipants;
        // game rules
        uint256 price;
        uint256 minDuration;
        uint256 noWinnerProbability;
        uint256[] prizes;
        uint256 finalizerReward;
        uint256 redistributionReserve;
        // only updated wen ze round issa finalized
        uint256 randomness;
    }

    uint256 public roundId = 0;

    // gas on canto issa beri cheapo so we can jussa store all ze past rounds fora ez luke up
    mapping(uint256 => Round) public rounds;
    // participant id issa 1-indexed (cuz 0 is same as false)
    mapping(uint256 => mapping(address => uint256)) public participantIds; // roundId => participant => participantId
    mapping(uint256 => mapping(uint256 => address)) public idParticipants; // roundId => participantId => participant

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SetOwner(address owner);
    event SetRandomnessClient(address rc);

    event SetPrice(uint256 price);
    event SetMinDuration(uint256 minDuration);
    event SetNoWinnerProbability(uint256 noWinnerProbability);
    event SetPrizes(uint256[] prizes);
    event SetFinalizerReward(uint256 finalizerReward);
    event SetRedistributionReserve(uint256 redistributionReserve);

    event WonPrize(uint256 indexed roundId, address indexed participant, uint256 prizeId, uint256 prizeAmount);
    event Redistribution(uint256 indexed roundId, address indexed participant, uint256 amount);

    event RoundStarted(uint256 indexed roundId);
    event RoundFinalized(uint256 indexed roundId, uint256 randomness);

    event ParticipantAdded(uint256 indexed roundId, address indexed participant, uint256 participantId);

    /*//////////////////////////////////////////////////////////////
                        HELPERS CUZ IM LAZYYYYYYYY
    //////////////////////////////////////////////////////////////*/
    modifier onlyOwner() {
        if (msg.sender != owner) revert NOT_OWNER();
        _;
    }

    function _isRoundStarted() internal view returns (bool) {
        return rounds[roundId].roundStartedAt != 0;
    }

    function _isRoundOver() internal view returns (bool) {
        return _isRoundStarted() && (block.timestamp >= rounds[roundId].roundStartedAt + rounds[roundId].minDuration);
    }

    modifier onlyRoundOver() {
        if (!_isRoundOver()) revert ROUND_NOT_OVER();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                NFT STUFF
    //////////////////////////////////////////////////////////////*/
    function tokenURI(uint256 id) public pure override returns (string memory) {
        // TODO: implement traits n stuff
        return string(abi.encodePacked("https://dumpingbandits.canto.life/nft/", Strings.toString(id)));
    }

    /*//////////////////////////////////////////////////////////////
                            GAME RULE SETTERS
    //////////////////////////////////////////////////////////////*/
    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
        emit SetOwner(_owner);
    }

    function setRandomnessClient(address _rc) public onlyOwner {
        if (_rc == address(0)) revert ZERO_ADDRESS();
        rc = IRandomnessClient(_rc);
        emit SetRandomnessClient(_rc);
    }

    function setPrice(uint256 _price) public onlyOwner {
        defaultPrice = _price;
        emit SetPrice(_price);
    }

    function setMinDuration(uint256 _minDuration) public onlyOwner {
        defaultMinDuration = _minDuration;
        emit SetMinDuration(_minDuration);
    }

    function setNoWinnerProbability(uint256 _noWinnerProbability) public onlyOwner {
        defaultNoWinnerProbability = _noWinnerProbability;
        emit SetNoWinnerProbability(_noWinnerProbability);
    }

    function setPrizes(uint256[] memory _prizes) public onlyOwner {
        if (_prizes.length == 0) revert ZERO_WINNERS();
        defaultPrizes = _prizes;
        emit SetPrizes(_prizes);
    }

    function setFinalizerReward(uint256 _finalizerReward) public onlyOwner {
        defaultFinalizerReward = _finalizerReward;
        emit SetFinalizerReward(_finalizerReward);
    }

    function setRedistributionReserve(uint256 _redistributionReserve) public onlyOwner {
        defaultRedistributionReserve = _redistributionReserve;
        emit SetRedistributionReserve(_redistributionReserve);
    }

    /*//////////////////////////////////////////////////////////////
                                GAME LOGIC
    //////////////////////////////////////////////////////////////*/
    function _startRound() internal {
        Round memory round = Round({
            roundStartedAt: block.timestamp,
            price: defaultPrice,
            minDuration: defaultMinDuration,
            noWinnerProbability: defaultNoWinnerProbability,
            prizes: defaultPrizes,
            finalizerReward: defaultFinalizerReward,
            redistributionReserve: defaultRedistributionReserve,
            totalParticipants: 0,
            randomness: 0
        });

        rounds[roundId] = round;
        emit RoundStarted(roundId);
    }

    function participate() public payable nonReentrant {
        if (msg.value != rounds[roundId].price) revert WRONG_PRICE();
        if (participantIds[roundId][msg.sender] != 0) revert ALREADY_PARTICIPATED();
        if (!_isRoundStarted()) {
            _startRound();
        }

        // add participant to the current round
        unchecked {
            rounds[roundId].totalParticipants++;
        }
        uint256 participantId = rounds[roundId].totalParticipants;
        participantIds[roundId][msg.sender] = participantId;
        idParticipants[roundId][participantId] = msg.sender;

        emit ParticipantAdded(roundId, msg.sender, participantId);
    }

    function finalizeRound() public onlyRoundOver nonReentrant {
        uint256 randomness = rc.generateRandomness();

        // update round struct
        rounds[roundId].randomness = randomness;

        // derive winners from randomness
        uint256[] memory winners = _deriveWinner(randomness);
        if (winners.length == 0) {
            _handleRedistribution();
        } else {
            _handlePrizes(winners);
        }

        // transfer finalizer reward to msg.sender then handover ze rest
        SafeTransferLib.safeTransferETH(msg.sender, rounds[roundId].finalizerReward);
        _handleLeftOver();
        emit RoundFinalized(roundId, randomness);

        // move on to ze next round (but issa not started yet)
        unchecked {
            roundId++;
        }
    }

    function _handlePrizes(uint256[] memory winners) internal {
        uint256 poolSize = address(this).balance - rounds[roundId].finalizerReward;
        for (uint256 i = 0; i < winners.length; i++) {
            // TODO: add NFT stuff here
            address winner = idParticipants[roundId][winners[i]];
            uint256 prizeAmount = poolSize.mulWadDown(rounds[roundId].prizes[i]);

            SafeTransferLib.safeTransferETH(winner, prizeAmount);
            emit WonPrize(roundId, winner, i, prizeAmount);
        }
    }

    function _handleRedistribution() internal {
        uint256 totalParticipants = rounds[roundId].totalParticipants;
        uint256 price = rounds[roundId].price;
        uint256 poolSize = price.mulWadDown(totalParticipants * 1e18) - rounds[roundId].finalizerReward;
        uint256 amount = poolSize.divWadDown(totalParticipants * 1e18);
        for (uint256 i = 1; i <= totalParticipants; i++) {
            // TODO: add NFT stuff here
            address participant = idParticipants[roundId][i];

            SafeTransferLib.safeTransferETH(participant, amount);
            emit Redistribution(roundId, participant, amount);
        }
    }

    function _handleLeftOver() internal {
        // TODO: alternative to burning?
        uint256 redistributionReserve = rounds[roundId].redistributionReserve.mulWadDown(address(this).balance);
        uint256 leftOver = address(this).balance - redistributionReserve;
        SafeTransferLib.safeTransferETH(address(0), leftOver);
    }

    // derive winnas froma random numba, based on current game configs
    function _deriveWinner(uint256 _randomness) internal view returns (uint256[] memory) {
        // if no winner, return empty array
        if (_randomness % (1e18) < rounds[roundId].noWinnerProbability) {
            return new uint256[](0);
        }

        uint256 prizesCount = rounds[roundId].prizes.length;
        uint256 totalParticipants = rounds[roundId].totalParticipants;

        uint256[] memory winners = new uint256[](prizesCount);
        uint256 winnerCount = 0;

        // else, derive winners
        for (uint256 i = 0; i < prizesCount; i++) {
            uint256 winnerId = _randomness % totalParticipants + 1;
            winners[i] = winnerId;
            winnerCount++;
            _randomness = _randomness / totalParticipants;
            // if _randomness gets too short, hash it again
            if (_randomness < 1e8) {
                _randomness = uint256(keccak256(abi.encodePacked(_randomness, block.timestamp)));
            }

            // TODO: dedupe
        }

        return winners;
    }
}
