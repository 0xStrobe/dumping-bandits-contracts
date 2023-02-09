// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IRandomnessClient} from "./interfaces/IRandomnessClient.sol";

error NOT_OWNER();
error WRONG_PRICE();
error ZERO_WINNERS();
error ROUND_NOT_STARTED();
error ROUND_NOT_OVER();
error ZERO_ADDRESS();

contract DumpingBandits is ERC721, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public owner;
    IRandomnessClient public rc;

    constructor(address _rc) ERC721("Dumping Bandits", "BANDIT") {
        if (_rc == address(0)) revert ZERO_ADDRESS();
        owner = msg.sender;
        rc = IRandomnessClient(_rc);
    }

    uint256 public roundId = 0;

    /*//////////////////////////////////////////////////////////////
                                GAME RULES
    //////////////////////////////////////////////////////////////*/
    // uh yis indeed, dis can be modified by owner butta only applies to ze next round (current round issa not affected)
    uint256 public price = 10 ether;
    uint256 public minDuration = 15 minutes;
    uint256 public noWinnerProbability = 0.00_0001 ether; // 0.0001%
    uint256[] public prizes = [0.4 ether, 0.25 ether, 0.15 ether]; // take home 40%, 25%, 15% of ze pot

    uint256 public roundStartedAt = 0;
    uint256 public totalParticipants = 0;

    uint256 public finalizerReward = 10 ether;

    /*//////////////////////////////////////////////////////////////
                            HISTORYYYYYYYYY
    //////////////////////////////////////////////////////////////*/
    struct Round {
        uint256 id;
        uint256 randomness;
        uint256 price;
        uint256 minDuration;
        uint256 totalWinners;
        uint256 noWinnerProbability;
        // ze following issa only updated wen ze round issa finalized
        uint256 roundStartedAt;
        uint256 totalParticipants;
    }

    // gas on canto issa beri cheapo so we can jussa store all ze past rounds fora ez luke up
    mapping(uint256 => Round) public rounds;
    // participant id issa 1-indexed
    mapping(uint256 => mapping(address => uint256)) public participantIds; // roundId => participant => participantId
    mapping(uint256 => mapping(uint256 => address)) public idParticipants; // roundId => participantId => participant

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SetOwner(address owner);
    event SetRandomnessClient(address rc);
    event SetPrice(uint256 price);
    event SetMinDuration(uint256 minDuration);
    event SetFinalizerReward(uint256 finalizerReward);
    event SetTotalWinners(uint256 totalWinners);
    event SetNoWinnerProbability(uint256 noWinnerProbability);
    event SetPrizes(uint256[] prizes);

    event WonPrize(uint256 indexed roundId, address indexed participant, uint256 winnerId, uint256 prizeAmount);
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
        return roundStartedAt != 0;
    }

    function _isRoundOver() internal view returns (bool) {
        return _isRoundStarted() && (block.timestamp >= roundStartedAt + minDuration);
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
        price = _price;
        emit SetPrice(_price);
    }

    function setMinDuration(uint256 _minDuration) public onlyOwner {
        minDuration = _minDuration;
        emit SetMinDuration(_minDuration);
    }

    function setFinalizerReward(uint256 _finalizerReward) public onlyOwner {
        finalizerReward = _finalizerReward;
        emit SetFinalizerReward(_finalizerReward);
    }

    function setNoWinnerProbability(uint256 _noWinnerProbability) public onlyOwner {
        noWinnerProbability = _noWinnerProbability;
        emit SetNoWinnerProbability(_noWinnerProbability);
    }

    function setPrizes(uint256[] memory _prizes) public onlyOwner {
        if (_prizes.length == 0) revert ZERO_WINNERS();
        prizes = _prizes;
        emit SetPrizes(_prizes);
    }

    /*//////////////////////////////////////////////////////////////
                                GAME LOGIC
    //////////////////////////////////////////////////////////////*/
    function _startRound() internal {
        unchecked {
            roundId++;
        }
        totalParticipants = 0;
        roundStartedAt = block.timestamp;

        Round memory round = Round({
            id: roundId,
            randomness: 0,
            price: price,
            minDuration: minDuration,
            totalWinners: prizes.length,
            noWinnerProbability: noWinnerProbability,
            roundStartedAt: roundStartedAt,
            totalParticipants: totalParticipants
        });

        rounds[roundId] = round;
        emit RoundStarted(roundId);
    }

    function participate() public payable nonReentrant {
        if (msg.value != price) revert WRONG_PRICE();
        if (!_isRoundStarted()) {
            _startRound();
        }

        // add participant to the current round
        unchecked {
            totalParticipants++;
        }
        participantIds[roundId][msg.sender] = totalParticipants;
        idParticipants[roundId][totalParticipants] = msg.sender;

        emit ParticipantAdded(roundId, msg.sender, totalParticipants);
    }

    function finalizeRound() public onlyRoundOver nonReentrant {
        uint256 randomness = rc.generateRandomness();

        // update round struct
        rounds[roundId].randomness = randomness;
        rounds[roundId].totalParticipants = totalParticipants;

        // derive winners from randomness
        uint256[] memory winners = _deriveWinner(randomness);
        if (winners.length == 0) {
            _handleRedistribution();
        } else {
            _handlePrizes(winners);
        }

        // transfer finalizer reward to msg.sender then handover ze rest
        payable(msg.sender).transfer(finalizerReward);
        _handleLeftOver();
        emit RoundFinalized(roundId, randomness);
    }

    function _handlePrizes(uint256[] memory winners) internal {
        uint256 poolSize = address(this).balance - finalizerReward;
        for (uint256 i = 0; i < winners.length; i++) {
            // TODO: add NFT stuff here
            address winner = idParticipants[roundId][winners[i]];
            uint256 prizeAmount = poolSize.mulWadDown(prizes[i]);

            payable(winner).transfer(prizeAmount);
            emit WonPrize(roundId, winner, i, prizeAmount);
        }
    }

    function _handleRedistribution() internal {
        uint256 poolSize = address(this).balance - finalizerReward;
        uint256 amount = poolSize.divWadDown(totalParticipants * 1e18);
        for (uint256 i = 1; i <= totalParticipants; i++) {
            // TODO: add NFT stuff here
            address participant = idParticipants[roundId][i];

            payable(participant).transfer(amount);
            emit Redistribution(roundId, participant, amount);
        }
    }

    function _handleLeftOver() internal {
        // TODO: alternative to burning?
        payable(address(0)).transfer(address(this).balance);
    }

    // derive winnas froma random numba, based on current game configs
    function _deriveWinner(uint256 _randomness) internal view returns (uint256[] memory) {
        // TODO: implement
    }
}
