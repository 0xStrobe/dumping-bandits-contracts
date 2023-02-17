// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import "solmate/utils/SafeTransferLib.sol";
import "openzeppelin-contracts/contracts/utils/Strings.sol";

import {IRandomnessClient} from "./interfaces/IRandomnessClient.sol";
import {IBanditTreasury} from "./interfaces/IBanditTreasury.sol";

error NOT_OWNER();
error WRONG_PRICE();
error ZERO_WINNERS();
error NOT_STARTED_YET();
error CANT_FINALIZE_YET();
error ZERO_ADDRESS();
error ALREADY_PARTICIPATED();
error TOO_MANY();
error TOO_MANY_PRIZES();

contract DumpingBandits is ERC721, ReentrancyGuard {
    using FixedPointMathLib for uint256;

    address public owner;
    IRandomnessClient public rc;
    IBanditTreasury public treasury;

    string public baseURI = "https://dumpingbandits/nft/";

    constructor(address _rc, address _treasury) ERC721("Dumping Bandits", "BANDIT") {
        if (_rc == address(0) || _treasury == address(0)) revert ZERO_ADDRESS();
        owner = msg.sender;
        emit SetOwner(owner);

        rc = IRandomnessClient(_rc);
        emit SetRandomnessClient(address(rc));

        treasury = IBanditTreasury(_treasury);
        emit SetTreasury(address(treasury));
    }

    /*//////////////////////////////////////////////////////////////
                                GAME RULES
    //////////////////////////////////////////////////////////////*/
    uint256 public price = 10 ether;
    uint256 public minDuration = 15 minutes;
    uint256 public everyoneWinsProbability = 0.00_0001 ether; // 0.0001%
    uint256[] public prizes = [0.4 ether, 0.25 ether, 0.15 ether]; // take home 40%, 25%, 15% of ze pot
    uint256 public finalizerReward = 5 ether;
    uint256 public treasuryReserve = 0.2 ether; // send 20% per round to ze treasury as house monies

    /*//////////////////////////////////////////////////////////////
                                GAME STATE
    //////////////////////////////////////////////////////////////*/
    uint256 public roundStartedAt = 0;
    uint256 public roundParticipants = 0;

    uint256 public roundId = 0;
    uint256 public lastRoundLastTokenId = 0;

    /*//////////////////////////////////////////////////////////////
                                GAME HISTORY
    //////////////////////////////////////////////////////////////*/
    struct Round {
        address[] winners;
        uint256 randomness;
        uint256 participants;
    }

    // gas on canto issa beri cheapo so we can jussa store all ze past rounds fora ez luke up
    mapping(uint256 => Round) public rounds; // roundId => Round
    mapping(uint256 => uint256) public tokenIdRound; // tokenId => roundId

    function prizeRank(uint256 _tokenId) public view returns (uint256) {
        uint256 _roundId = tokenIdRound[_tokenId];
        Round storage round = rounds[_roundId];
        bool everyoneWins = (round.randomness % 1 ether <= everyoneWinsProbability);
        if (everyoneWins) return type(uint256).max;

        for (uint256 i = 1; i < round.winners.length; i++) {
            if (round.winners[i] == ownerOf(_tokenId)) return i + 1;
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SetOwner(address owner);
    event SetRandomnessClient(address rc);
    event SetTreasury(address treasury);

    event SetPrice(uint256 price);
    event SetMinDuration(uint256 minDuration);
    event SetEveryoneWinsProbability(uint256 everyoneWinsProbability);
    event SetPrizes(uint256[] prizes);
    event SetFinalizerReward(uint256 finalizerReward);
    event SetTreasuryReserve(uint256 treasuryReserve);
    event SetBaseURI(string baseURI);

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
        return roundStartedAt != 0;
    }

    function _canFinalize() internal view returns (bool) {
        return _isRoundStarted() && (block.timestamp >= roundStartedAt + minDuration);
    }

    modifier onlyCanFinalize() {
        if (!_canFinalize()) revert CANT_FINALIZE_YET();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                NFT STUFF
    //////////////////////////////////////////////////////////////*/
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, Strings.toString(_tokenId)));
    }

    function tokenInfo(uint256 _tokenId) public view returns (string memory) {
        uint256 _roundId = tokenIdRound[_tokenId];
        Round storage round = rounds[_roundId];
        uint256 _totalWinners = round.winners.length;
        uint256 _prizeRank = prizeRank(_tokenId);

        if (_prizeRank != type(uint256).max) {
            return string(abi.encodePacked("Round ", Strings.toString(_roundId), " - Everyone wins!"));
        } else if (_prizeRank == 0) {
            return string(abi.encodePacked("Round ", Strings.toString(_roundId), " - Did not win."));
        } else {
            return string(
                abi.encodePacked(
                    "Round ",
                    Strings.toString(_roundId),
                    " - ",
                    Strings.toString(_prizeRank),
                    "/",
                    Strings.toString(_totalWinners)
                )
            );
        }
    }

    function getOwnerTokenIds(address _owner) public view returns (uint256[] memory) {
        uint256 _balance = balanceOf(_owner);
        if (_balance == 0) return new uint256[](0);
        uint256[] memory _tokens = new uint256[](_balance);
        uint256 tokenCount = 0;
        for (uint256 i = 1; i <= lastRoundLastTokenId + roundParticipants; i++) {
            if (ownerOf(i) == _owner) {
                _tokens[tokenCount] = i;
                tokenCount++;
            }
        }
        return _tokens;
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
        emit SetRandomnessClient(address(rc));
    }

    function setTreasury(address _treasury) public onlyOwner {
        if (_treasury == address(0)) revert ZERO_ADDRESS();
        treasury = IBanditTreasury(_treasury);
        emit SetTreasury(address(treasury));
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
        emit SetPrice(price);
    }

    function setMinDuration(uint256 _minDuration) public onlyOwner {
        minDuration = _minDuration;
        emit SetMinDuration(minDuration);
    }

    function setEveryoneWinsProbability(uint256 _everyoneWinsProbability) public onlyOwner {
        everyoneWinsProbability = _everyoneWinsProbability;
        emit SetEveryoneWinsProbability(everyoneWinsProbability);
    }

    function setPrizes(uint256[] memory _prizes) public onlyOwner {
        if (_prizes.length == 0) revert ZERO_WINNERS();
        if (_prizes.length >= type(uint32).max) revert TOO_MANY();
        uint256 totalPrizes = 0;
        for (uint256 i = 0; i < _prizes.length; i++) {
            totalPrizes += _prizes[i];
        }
        if (totalPrizes + treasuryReserve > 1 ether) {
            revert TOO_MANY_PRIZES();
        }
        prizes = _prizes;
        emit SetPrizes(prizes);
    }

    function setFinalizerReward(uint256 _finalizerReward) public onlyOwner {
        finalizerReward = _finalizerReward;
        emit SetFinalizerReward(finalizerReward);
    }

    function setTreasuryReserve(uint256 _treasuryReserve) public onlyOwner {
        treasuryReserve = _treasuryReserve;
        emit SetTreasuryReserve(_treasuryReserve);
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
        emit SetBaseURI(baseURI);
    }

    /*//////////////////////////////////////////////////////////////
                                GAME LOGIC
    //////////////////////////////////////////////////////////////*/
    function _startRound() internal {
        roundId++;
        lastRoundLastTokenId = lastRoundLastTokenId + roundParticipants;

        roundStartedAt = block.timestamp;
        roundParticipants = 0;

        emit RoundStarted(roundId);
    }

    function participate() public payable nonReentrant {
        if (msg.value != price) revert WRONG_PRICE();
        if (!_isRoundStarted()) {
            _startRound();
        }

        roundParticipants++;
        uint256 thisTokenId = lastRoundLastTokenId + roundParticipants;
        tokenIdRound[thisTokenId] = roundId;
        _safeMint(msg.sender, thisTokenId);

        emit ParticipantAdded(roundId, msg.sender, thisTokenId);
    }

    function finalizeRound() public onlyCanFinalize nonReentrant {
        uint256 randomness = rc.getRandomness();
        address[] memory winners = _deriveWinner(randomness);

        Round memory round = Round({winners: winners, randomness: randomness, participants: roundParticipants});
        rounds[roundId] = round;

        if (winners.length == 0) {
            _handleRedistribution();
        } else {
            _handlePrizes(winners);
        }

        // transfer finalizer reward to msg.sender then handover ze rest
        SafeTransferLib.safeTransferETH(msg.sender, finalizerReward);
        _handleLeftOver();

        roundStartedAt = 0;
        roundParticipants = 0;
        emit RoundFinalized(roundId, randomness);
    }

    function _handlePrizes(address[] memory winners) internal {
        uint256 poolSize = (address(this).balance - finalizerReward).mulWadDown(1 ether - treasuryReserve);
        for (uint256 i = 0; i < winners.length; i++) {
            address winner = winners[i];
            uint256 prizeAmount = poolSize.mulWadDown(prizes[i]);

            SafeTransferLib.safeTransferETH(winner, prizeAmount);
            emit WonPrize(roundId, winner, i, prizeAmount);
        }
    }

    function _handleRedistribution() internal {
        uint256 poolSize = (address(this).balance - finalizerReward).mulWadDown(1 ether - treasuryReserve);
        uint256 amount = poolSize.divWadDown(roundParticipants * 1e18);
        for (uint256 i = 1; i <= roundParticipants; i++) {
            address participant = ownerOf(lastRoundLastTokenId + i);
            SafeTransferLib.safeTransferETH(participant, amount);
            emit Redistribution(roundId, participant, amount);
        }
    }

    function _handleLeftOver() internal {
        SafeTransferLib.safeTransferETH(address(treasury), address(this).balance);
    }

    // derive winnas froma random numba, based on current game configs
    function _deriveWinner(uint256 _randomness) internal view returns (address[] memory) {
        // if no winner, return empty array
        if (_randomness % (1e18) < everyoneWinsProbability) {
            return new address[](0);
        }

        // else, derive winners
        uint256 prizesCount = prizes.length;

        uint256[] memory winnerIds = _rng(_randomness, uint32(roundParticipants), uint32(prizesCount));
        address[] memory winners = new address[](winnerIds.length);
        for (uint256 i = 0; i < winnerIds.length; i++) {
            winners[i] = ownerOf(winnerIds[i] + lastRoundLastTokenId);
        }

        return winners;
    }

    function _lcg(uint256 _seed) internal pure returns (uint32) {
        // operate on 48bit at each iterashun but returns only ze 32 most significant bits (betta statistico distro)
        uint256 a = 25214903917;
        uint256 c = 11;
        uint256 m = 281474976710656; // 2^48
        return uint32((a * _seed + c) % m >> 16);
    }

    /// generate `_count` random numbers between 1 and _max (inclusive) without duplicates
    function _rng(uint256 _seed, uint32 _max, uint32 _count) internal pure returns (uint256[] memory) {
        uint256[] memory results = new uint256[](_count);
        uint256 currentSeed = _seed;
        uint256 i = 0;

        while (i < _count) {
            currentSeed = _lcg(currentSeed);
            uint256 randomNumber = currentSeed % _max + 1;

            bool unique = true;
            for (uint256 j = 0; j < i; j++) {
                if (results[j] == randomNumber) {
                    unique = false;
                    break;
                }
            }

            if (unique) {
                results[i] = randomNumber;
                i++;
            }
        }

        return results;
    }
}
