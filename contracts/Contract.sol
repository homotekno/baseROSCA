// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract BaseROSCA is ReentrancyGuard, VRFConsumerBaseV2Plus {
    
    constructor(uint256 subscriptionId) VRFConsumerBaseV2Plus(vrfCoordinator) {

        // vrf
        s_subscriptionId = subscriptionId;
        // 51624121128218574993867206953409889168951677118151954112797997374876714226754
        
        admin = msg.sender;
        baseContractUSDC = IERC20(0x42F253D3E3Ee7Dd8676DE6075c15A252879FA9cF);


    }

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    // modifiers

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    modifier onlyAdmin(){
        require(msg.sender == admin, "only admin can call this function !!");
        _;
    }
    modifier activeROSCA(){
        require(statusROSCA, "No active ROSCA rn!!");
        _;
    }
    modifier withinDeadlineWindow(){
        require( block.timestamp < deadlineforRound[currentRound], "Deadline for this round has passed, sorry!!");
        _;
    }
    modifier outsideDeadlineWindow(){
        require( block.timestamp > deadlineforRound[currentRound], "Deadline for this round has not passed, please try after sometime!!");
        _;
    }
    
    // modifier kickoffWindow(){
    //     require( block.timestamp > kickoffTimeforRound[currentRound], "It's not time for the round to start yet, sorry!!");
    //     _;
    // }


    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //
    
    // functions called by admin

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //


    // give access/allowlist user
    function vettUser(address _userAddress, string calldata _username) external nonReentrant onlyAdmin{
        isAllowed[_userAddress] = true;
        username[_userAddress] = _username;    
    }

    // start ROSCA instence
    function startROSCAInstance(uint256 _slots, uint256 _maxContributionAmount, uint256 _feeBasisPoints, uint256 _duration) external nonReentrant onlyAdmin{

        require(!statusROSCA,"There is another ROSCA active !!");
        currentRound = 0;
        statusROSCA = true;

        slots = _slots;
        slotsLeft = _slots;
        maxContributionAmount = _maxContributionAmount * 10**18;
        fullROSCPot = _slots * _maxContributionAmount * 10**18;
        fees = _feeBasisPoints * _maxContributionAmount * 10**14 ;
        duration = _duration;

        insuranceBudget = 0;

        kickoffTime = block.timestamp;
        for(uint256 i = 1; i <= slots; i++){
            uint256 z = i-1;
            kickoffTimeforRound[i] = kickoffTime + (z * _duration);
            deadlineforRound[i] = kickoffTime + (i * _duration); // - 1 days sunday prize 
            prizeMoneyCalledorNot[i] = false;
        }
        discountOfferedforRound[0] = 0;
    }

    // insurance budget - > anyone?
    function securityGuarantee() external nonReentrant onlyAdmin{
        
        uint256 insuranceContribution = fullROSCPot;

        insuranceBudget += insuranceContribution;
        require(baseContractUSDC.transferFrom(msg.sender, address(this), insuranceContribution), "Transaction failed !!");
    }



    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //
    
    // functions called by participants

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    // enroll
    // ======
    function enroll() external activeROSCA nonReentrant{

        enrollmentChecklist(msg.sender);

        slotsLeft--;

        createParticipantProfile(msg.sender);
    }
    
    function enrollmentChecklist(address _prospect) internal view {
        require(isAllowed[_prospect], "You do not have access!!");
        require(!isParticipant[_prospect], "you are already enrolled !!");
        require(slotsLeft > 0, "sorry slots are full !!");
        require(currentRound == 0, "fund has already started");
    }
    function createParticipantProfile(address _enrolledParticipant) internal {
        Participants.push(_enrolledParticipant);
        isParticipant[_enrolledParticipant] = true;
        userContributions[_enrolledParticipant] = 0;
        userDuesPending[_enrolledParticipant] = 0;
        userNoDueCertificate[_enrolledParticipant] = true;
        hasWon[_enrolledParticipant] = false;
        participantWonRound[_enrolledParticipant] = 0;
        hasDefaultedRound[_enrolledParticipant][0] = false; // edge case
    }

    // no due certificate
    // ==================
    function noDueCertificate() external activeROSCA nonReentrant{
        require(isParticipant[msg.sender], "You are not part of this ROSCA, sorry!!");
        uint256 pendingDue = userDuesPending[msg.sender];
        require(pendingDue > 0, "You do not have any pending dues to clear!!");
        require(!userNoDueCertificate[msg.sender], "You already maintain a no-due-certificate!!");

        require(baseContractUSDC.transferFrom(msg.sender, address(this), pendingDue), "Transaction failed !!");

        updateDueCertificate(msg.sender);
    }
    function updateDueCertificate(address _clearoor) internal {
        userDuesPending[_clearoor] = 0;
        userNoDueCertificate[_clearoor] = true;
    }

    // contribute
    // ==========
    function contribute() external activeROSCA withinDeadlineWindow nonReentrant{

        contributionCchecklist(msg.sender, currentRound);
        uint256 payorContribution =  calculateContributionAmountforParticipant(msg.sender, currentRound);
        updateParticipantContribution(msg.sender, currentRound);

        require(baseContractUSDC.transferFrom(msg.sender, address(this), payorContribution), "Transaction failed !!");
    }
    
    function contributionCchecklist(address _contributoor, uint256 _roundNumber) internal view {
        require(_roundNumber > 0 && _roundNumber <= slots, "All rounds are completed.");
        require(isParticipant[_contributoor], "You are not part of this ROSCA, sorry!!");
        require(userNoDueCertificate[_contributoor], "You need to clear dues to be eligible to contribute!!");
        require(userDuesPending[_contributoor] == 0, "You need to clear dues to be eligible to contribute!!");
        require(!hasPaidRound[_contributoor][_roundNumber], "you have already paid this round !!");
    }
    function calculateContributionAmountforParticipant(address _contributoor, uint256 _roundNumber) internal view returns(uint256) {
        // if default last round : return maxContribution : return discounted contribution
        uint256 previousRound = _roundNumber - 1;
        bool defaultStatusPrevRound = hasDefaultedRound[_contributoor][previousRound];

        if(defaultStatusPrevRound){
            return maxContributionAmount;
        } else {
            return contributionDueforRound[_roundNumber];
        }
    }
    function updateParticipantContribution(address _contributoor, uint256 _roundNumber) internal {
        // successful
        hasPaidRound[_contributoor][_roundNumber] = true;
        totalContributionforRound[_roundNumber] += contributionDueforRound[_roundNumber];
        userContributions[_contributoor] += contributionDueforRound[_roundNumber];
    }

    // bid
    // ===
    function bid(uint256 _bid) external activeROSCA withinDeadlineWindow nonReentrant{
        biddingChecklist(msg.sender, currentRound);

        require( _bid <= 24, "Bidding Range:  1% to 24%");
        require(_bid > winningBidforRound[currentRound], "new bids should be higher than the highest bid");
        if(_bid > winningBidforRound[currentRound]){
            winningBidforRound[currentRound] = _bid;
            winnerWinner = msg.sender;
            anyBidsforRound[currentRound] = true;
        }        
        updateParticipantBids(msg.sender, currentRound, _bid);        
    }
    
    function biddingChecklist(address _biddoor, uint256 _roundNumber) internal view {
        require(_roundNumber > 0 && _roundNumber < Participants.length, "No bidding for the last round!!");
        require(isParticipant[_biddoor], "you are not enrolled for this fund !!");
        require(!hasWon[_biddoor], "uh-oh! winners cannot bid, sorry !!");
        require(hasPaidRound[_biddoor][_roundNumber], "complete payment for the round to bid the pot !!");
    }
    function updateParticipantBids(address _contributoor, uint256 _roundNumber, uint256 _bidValue) internal {
        hasBidRound[_contributoor][_roundNumber] = true;
        participantBidforRound[_contributoor][_roundNumber] = _bidValue;
    }

    // cashout
    // =======
    function cashout() external activeROSCA nonReentrant{
        uint256 roundWonbyCashoutoor = cashoutChecklist(msg.sender);
        uint256 cashoutPrizeAmount = prizeMoneyforRound[roundWonbyCashoutoor];

        require(baseContractUSDC.transfer(msg.sender, cashoutPrizeAmount), "Token transfer failed");
        cashoutStatusforRound[roundWonbyCashoutoor] = true;
    }

    function cashoutChecklist(address _cashoutoor) internal view returns(uint256 _roundWonbyCashoutoor) {
        require(isParticipant[_cashoutoor], "you are not enrolled for this fund !!");
        require(userNoDueCertificate[_cashoutoor], "You need to clear dues to be eligible to cashout!!");
        require(userDuesPending[_cashoutoor] == 0, "You need to clear dues to be eligible to cashout!!");

        require(hasWon[_cashoutoor], "You can only cashout once you have won a round");
        uint256 roundWonbyCashoutoor = participantWonRound[_cashoutoor];
        require(roundWonbyCashoutoor != 0, "Something is wrong!!");
        require(!cashoutStatusforRound[roundWonbyCashoutoor], "Prize money for this round already cashed out!!");

        uint256 cashoutPrizeAmount = prizeMoneyforRound[roundWonbyCashoutoor];
        require(cashoutPrizeAmount > 0, "Something is wrong!!");

        uint256 tokenBalance = baseContractUSDC.balanceOf(address(this));
        require(tokenBalance >= cashoutPrizeAmount, "Not enough funds!!");

        return roundWonbyCashoutoor;
    }


    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //
    
    // functions called by protocol/automated

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    
    // start Loop
    // ==========
    function startLoop() external activeROSCA{

        // make sure it's called only once for each round timestamps
        loopChecklist(currentRound); // timekeeping
        currentRound++;
        initializeVariablesforRound(currentRound);
    }

    function loopChecklist(uint256 _roundNumber) internal view{
        require(_roundNumber < slots, "All rounds are completed.");
        // checklist make sure enrolments are complete before round 1
        uint256 nextRound = _roundNumber + 1;
        require( block.timestamp > kickoffTimeforRound[nextRound], "It's not time for the round to start yet, sorry!!");
    }

    function initializeVariablesforRound(uint256 _roundNumber) internal {

        for(uint256 i = 0; i < Participants.length; i++){
            hasPaidRound[Participants[i]][_roundNumber] = false;
            hasBidRound[Participants[i]][_roundNumber] = false;
            hasDefaultedRound[Participants[i]][_roundNumber] = false;
            participantBidforRound[Participants[i]][_roundNumber] = 0;
        }

        uint256 previousRound = _roundNumber - 1;
        totalContributionforRound[_roundNumber] = discountOfferedforRound[previousRound];
        contributionDueforRound[_roundNumber] = calculateContributionAmountforRound(_roundNumber);

        defaulterCountforRound[_roundNumber] = 0;
        penaltiesforRound[_roundNumber] = 0;
        insuranceClaimStatusforRound[_roundNumber] = false;
        insuranceClaimAmountforRound[_roundNumber] = 0;

        anyBidsforRound[currentRound] = false;
        prizeMoneyforRoundbeforeFees[_roundNumber] = 0; // whole pot - fees
        prizeMoneyforRound[_roundNumber] = 0;

        winningBidforRound[_roundNumber] = 0;
        raffleCalledforRound[_roundNumber] = false;
        winnerWinner = admin;
        winnerforRound[_roundNumber] = admin;

        delete Rafflelist;
        chainlinkRaffleWinner = admin;

        cashoutStatusforRound[_roundNumber] = false;
        feeCollectionStatusforRound[_roundNumber] = false;
    }

    function calculateContributionAmountforRound(uint256 _roundNumber) internal view returns(uint256){
        uint256 fullDueAmountforRound = fullROSCPot - totalContributionforRound[_roundNumber];
        uint256 contributionDueforNonDefaultedParticipants = fullDueAmountforRound / Participants.length; 
        return contributionDueforNonDefaultedParticipants;
    }

    // prize, winner and penalties
    // ===========================
    function prizeMoney() external activeROSCA nonReentrant{
        
        prizeMoneyChecklist(currentRound);
        raffleCalledforRound[currentRound] == false;
        // winner
        winnerforRound[currentRound] = winnerSelector(currentRound);
        if (raffleCalledforRound[currentRound] == false){

            fulfillPrizeWinnerInfo();
        }
    }
    
    function prizeMoneyChecklist(uint256 _roundNumber) internal view {
        require(_roundNumber <= slots, "All rounds are completed.");
        require(block.timestamp > deadlineforRound[_roundNumber], "Round deadline has not passed yet!!");
        require(!prizeMoneyCalledorNot[_roundNumber], "Already called prizeMoney once for this round!!");
    }
    function winnerSelector(uint256 _roundNumber) internal returns (address){
        // if last round -> last man standing // any bids -> highest bidder // no bids -> raffle among !hasWon
        if (_roundNumber == Participants.length){
            // winnerWinner = Participants.!hasWon;
            address lastManStanding;
            for(uint256 i = 0; i < Participants.length; i++){
               if(!hasWon[Participants[i]]){
                lastManStanding = Participants[i];
               }
            }
            return lastManStanding;
        } else if(anyBidsforRound[_roundNumber]){
            // highest bidder
            return winnerWinner;
        } else {
            // no bids = create rafflelist of non winners -> call lottery vrf            
            delete Rafflelist;
            for(uint256 i=0; i < Participants.length; i++){
                address nonWinner = Participants[i];
                if(!hasWon[nonWinner]){
                    Rafflelist.push(nonWinner);
                }
            }
            // call chainlink vrf
            randomRandom();
            raffleCalledforRound[_roundNumber] = true;
            return chainlinkRaffleWinner;
        }
    }
    function fulfillPrizeWinnerInfo() public {
        // insurance
        insuranceClaimAmountforRound[currentRound] = defaultsPenaltiesInsurance(currentRound);
        if(insuranceClaimAmountforRound[currentRound] > 0){
            claimInsurance(currentRound, insuranceClaimAmountforRound[currentRound]);
        }

        prizeMoneyforRoundbeforeFees[currentRound] = totalContributionforRound[currentRound] + insuranceClaimAmountforRound[currentRound];

        hasWon[winnerforRound[currentRound]] = true;
        participantWonRound[winnerforRound[currentRound]] = currentRound;
        // discount
        discountOfferedforRound[currentRound] = winningBidforRound[currentRound] * prizeMoneyforRoundbeforeFees[currentRound];
        discountOfferedforRound[currentRound] /= 100;
        // prize
        prizeMoneyforRound[currentRound] = prizeMoneyforRoundbeforeFees[currentRound] - discountOfferedforRound[currentRound]- fees;
        
        // fees
        collectProtocolFees(currentRound);

        prizeMoneyCalledorNot[currentRound] = true;

        if (currentRound == slots){
            statusROSCA = false;
            delete Rafflelist;
        }
    }
    function defaultsPenaltiesInsurance(uint256 _roundNumber) internal returns(uint256 _insuranceClaimAmount){
        // penalties in a different function
        for(uint256 i = 0; i < Participants.length; i++){
            if(!hasPaidRound[Participants[i]][_roundNumber]){
                hasDefaultedRound[Participants[i]][_roundNumber] = true;
                userDuesPending[Participants[i]] += maxContributionAmount;
                userNoDueCertificate[Participants[i]] = false;
                defaulterCountforRound[_roundNumber]++;
            }
        }
        // add up defaults or full pot minus total contributions currentround ??
        uint256 prizeShortage = fullROSCPot - totalContributionforRound[_roundNumber];  
        return prizeShortage;
    }
    function claimInsurance(uint256 _roundNumber, uint256 _claimAmountInsurance) internal {
        require(insuranceBudget > _claimAmountInsurance, "Not enough insurance budget!!");
        insuranceBudget -= _claimAmountInsurance;
        insuranceClaimStatusforRound[_roundNumber] = true;
    }
    function randomRandom() internal returns(uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest({
            keyHash: s_keyHash,
            subId: s_subscriptionId,
            requestConfirmations: requestConfirmations,
            callbackGasLimit: callbackGasLimit,
            numWords: numWords,
            // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
            extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false}))
        })
    );
    } // chainlink VRF
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {

        uint256 indexofWinner = randomWords[0] % Rafflelist.length;

        winnerforRound[currentRound] = Rafflelist[indexofWinner];
        
    }
    function collectProtocolFees(uint256 _roundNumber) internal {
        uint256 tokenBalance = baseContractUSDC.balanceOf(address(this));
        require(tokenBalance >= fees, "Not enough funds!!");

        require(baseContractUSDC.transfer(admin, fees), "Token transfer failed");
        feeCollectionStatusforRound[_roundNumber] = true;
    }
    function getParticipants() public view returns(address[] memory) {
        return Participants;
    }

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    
    // variables

    address public admin;
    IERC20 public baseContractUSDC;

    uint256 public kickoffTime;
    uint256 public duration;
    uint256 public maxContributionAmount;
    uint256 public fullROSCPot;
    uint256 public fees;

    uint256 public slots;
    uint256 public slotsLeft;
    uint256 public currentRound;

    address[] public Participants;

    mapping(address => bool) public isParticipant;
    mapping(address => uint256) public userContributions;
    mapping(address => uint256) public userDuesPending;
    mapping(address => bool) public hasWon;
    mapping(address => uint256) public participantWonRound;
    mapping(address => bool) public userNoDueCertificate;

    mapping(uint256 => uint256) public deadlineforRound;
    mapping(address => mapping(uint256 => bool)) public hasPaidRound;
    mapping(address => mapping(uint256 => bool)) public hasDefaultedRound;
    mapping(address => mapping(uint256 => bool)) public hasBidRound;
    mapping(address => mapping(uint256 => uint256)) public participantBidforRound;
        
    bool public statusROSCA;

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    // admin variables

    uint256 public insuranceBudget;
    mapping(address => bool) public isAllowed;
    mapping(address => string) public username;
    mapping(uint256 => bool) public prizeMoneyCalledorNot;

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    mapping(uint256 => uint256) public kickoffTimeforRound;
    mapping(uint256 => uint256) public totalContributionforRound;
    mapping(uint256 => uint256) public contributionDueforRound;

    mapping(uint256 => uint256) public defaulterCountforRound; // duplicate ??
    mapping(uint256 => uint256) public insuranceClaimAmountforRound;
    mapping(uint256 => bool) public insuranceClaimStatusforRound;
    mapping(uint256 => uint256) public penaltiesforRound;

    mapping(uint256 => bool) public anyBidsforRound;
    mapping(uint256 => uint256) public winningBidforRound;
    mapping(uint256 => uint256) public discountOfferedforRound; // duplicate ??
    mapping(uint256 => uint256) public prizeMoneyforRoundbeforeFees;
    mapping(uint256 => uint256) public prizeMoneyforRound;

    mapping(uint256 => bool) public raffleCalledforRound;

    address public winnerWinner;
    address public chainlinkRaffleWinner;
    mapping(uint256 => address) public winnerforRound;

    mapping(uint256 => bool) public cashoutStatusforRound;
    mapping(uint256 => bool) public feeCollectionStatusforRound;

    address[] public Rafflelist;

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

    // chainlink vrf variables

    uint256 public s_subscriptionId;
    address public vrfCoordinator = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    bytes32 public s_keyHash = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //


    // ==xxxxxxx=========xxxxxxx=========xxxxxxx=========xxxxxxx== //

}