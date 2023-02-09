// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IRandomnessClient} from "./interfaces/IRandomnessClient.sol";

error NOT_OWNER();
error WRONG_PRICE();
error ROUND_NOT_STARTED();
error ROUND_NOT_OVER();
error ZERO_ADDRESS();

contract DumpingBandits is ERC721, ReentrancyGuard {
    using SafeTransferLib for ERC20;

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
    event OwnerSet(address owner);
    event RandomnessClientSet(address rc);
    event PriceSet(uint256 price);
    event MinDurationSet(uint256 minDuration);
    event FinalizerRewardSet(uint256 finalizerReward);

    event RoundStarted(uint256 indexed roundId, uint256 minDuration);
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
        emit OwnerSet(_owner);
    }

    function setRandomnessClient(address _rc) public onlyOwner {
        if (_rc == address(0)) revert ZERO_ADDRESS();
        rc = IRandomnessClient(_rc);
        emit RandomnessClientSet(_rc);
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
        emit PriceSet(_price);
    }

    function setMinDuration(uint256 _minDuration) public onlyOwner {
        minDuration = _minDuration;
        emit MinDurationSet(_minDuration);
    }

    function setFinalizerReward(uint256 _finalizerReward) public onlyOwner {
        finalizerReward = _finalizerReward;
        emit FinalizerRewardSet(_finalizerReward);
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
            roundStartedAt: roundStartedAt,
            totalParticipants: totalParticipants
        });

        rounds[roundId] = round;
        emit RoundStarted(roundId, minDuration);
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
        // TODO: distribute or make claimable the prize

        // transfer finalizer reward to msg.sender and burn the rest
        payable(msg.sender).transfer(finalizerReward);
        payable(address(0)).transfer(address(this).balance);
        emit RoundFinalized(roundId, randomness);
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
