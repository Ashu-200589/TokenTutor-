// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title TokenTutor
 * @dev A decentralized education platform connecting students with tutors
 * @author TokenTutor Team
 */
contract TokenTutor {
    // State variables
    address public owner;
    uint256 public platformFee = 250; // 2.5% fee (out of 10000)
    uint256 public nextTutorId = 1;
    uint256 public nextSessionId = 1;
    
    // Structs
    struct Tutor {
        uint256 id;
        address tutorAddress;
        string name;
        string subject;
        uint256 hourlyRate; // in wei
        uint256 rating; // out of 5 stars (multiplied by 100)
        uint256 totalSessions;
        bool isActive;
    }
    
    struct Session {
        uint256 id;
        uint256 tutorId;
        address student;
        uint256 duration; // in hours
        uint256 totalCost;
        uint256 sessionTime;
        bool isCompleted;
        bool isPaid;
        uint256 rating; // student's rating for this session
    }
    
    // Mappings
    mapping(uint256 => Tutor) public tutors;
    mapping(uint256 => Session) public sessions;
    mapping(address => uint256[]) public tutorSessions; // tutor address to session IDs
    mapping(address => uint256[]) public studentSessions; // student address to session IDs
    mapping(address => uint256) public tutorBalance;
    
    // Events
    event TutorRegistered(uint256 indexed tutorId, address indexed tutorAddress, string name);
    event SessionBooked(uint256 indexed sessionId, uint256 indexed tutorId, address indexed student);
    event SessionCompleted(uint256 indexed sessionId, uint256 rating);
    event PaymentReleased(uint256 indexed sessionId, uint256 amount);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyActiveTutor(uint256 _tutorId) {
        require(tutors[_tutorId].isActive, "Tutor is not active");
        require(tutors[_tutorId].tutorAddress != address(0), "Tutor does not exist");
        _;
    }
    
    modifier onlySessionParticipant(uint256 _sessionId) {
        Session memory session = sessions[_sessionId];
        require(
            msg.sender == session.student || 
            msg.sender == tutors[session.tutorId].tutorAddress,
            "Only session participants can call this function"
        );
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Register as a tutor on the platform
     * @param _name Tutor's name
     * @param _subject Subject they teach
     * @param _hourlyRate Rate per hour in wei
     */
    function registerTutor(
        string memory _name,
        string memory _subject,
        uint256 _hourlyRate
    ) external {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_subject).length > 0, "Subject cannot be empty");
        require(_hourlyRate > 0, "Hourly rate must be greater than 0");
        
        tutors[nextTutorId] = Tutor({
            id: nextTutorId,
            tutorAddress: msg.sender,
            name: _name,
            subject: _subject,
            hourlyRate: _hourlyRate,
            rating: 0,
            totalSessions: 0,
            isActive: true
        });
        
        emit TutorRegistered(nextTutorId, msg.sender, _name);
        nextTutorId++;
    }
    
    /**
     * @dev Book a tutoring session
     * @param _tutorId ID of the tutor
     * @param _duration Duration of session in hours
     */
    function bookSession(uint256 _tutorId, uint256 _duration) 
        external 
        payable 
        onlyActiveTutor(_tutorId) 
    {
        require(_duration > 0, "Duration must be greater than 0");
        require(msg.sender != tutors[_tutorId].tutorAddress, "Tutors cannot book sessions with themselves");
        
        uint256 totalCost = tutors[_tutorId].hourlyRate * _duration;
        require(msg.value >= totalCost, "Insufficient payment");
        
        sessions[nextSessionId] = Session({
            id: nextSessionId,
            tutorId: _tutorId,
            student: msg.sender,
            duration: _duration,
            totalCost: totalCost,
            sessionTime: block.timestamp,
            isCompleted: false,
            isPaid: false,
            rating: 0
        });
        
        tutorSessions[tutors[_tutorId].tutorAddress].push(nextSessionId);
        studentSessions[msg.sender].push(nextSessionId);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit SessionBooked(nextSessionId, _tutorId, msg.sender);
        nextSessionId++;
    }
    
    /**
     * @dev Complete a session and release payment
     * @param _sessionId ID of the session
     * @param _rating Rating given by student (1-5 stars, multiplied by 100)
     */
    function completeSession(uint256 _sessionId, uint256 _rating) 
        external 
        onlySessionParticipant(_sessionId) 
    {
        Session storage session = sessions[_sessionId];
        require(!session.isCompleted, "Session already completed");
        require(_rating >= 100 && _rating <= 500, "Rating must be between 1-5 stars (100-500)");
        
        session.isCompleted = true;
        session.rating = _rating;
        
        // Calculate platform fee and tutor payment
        uint256 platformFeeAmount = (session.totalCost * platformFee) / 10000;
        uint256 tutorPayment = session.totalCost - platformFeeAmount;
        
        // Update tutor stats
        Tutor storage tutor = tutors[session.tutorId];
        tutor.totalSessions++;
        
        // Update tutor rating (simple average)
        if (tutor.rating == 0) {
            tutor.rating = _rating;
        } else {
            tutor.rating = (tutor.rating + _rating) / 2;
        }
        
        // Add to tutor's balance
        tutorBalance[tutor.tutorAddress] += tutorPayment;
        
        // Transfer platform fee to owner
        payable(owner).transfer(platformFeeAmount);
        
        session.isPaid = true;
        
        emit SessionCompleted(_sessionId, _rating);
        emit PaymentReleased(_sessionId, tutorPayment);
    }
    
    // View functions
    function getTutor(uint256 _tutorId) external view returns (Tutor memory) {
        return tutors[_tutorId];
    }
    
    function getSession(uint256 _sessionId) external view returns (Session memory) {
        return sessions[_sessionId];
    }
    
    function getTutorSessions(address _tutor) external view returns (uint256[] memory) {
        return tutorSessions[_tutor];
    }
    
    function getStudentSessions(address _student) external view returns (uint256[] memory) {
        return studentSessions[_student];
    }
    
    function withdrawEarnings() external {
        uint256 balance = tutorBalance[msg.sender];
        require(balance > 0, "No earnings to withdraw");
        
        tutorBalance[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
    }
    
    // Owner functions
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Platform fee cannot exceed 10%");
        platformFee = _newFee;
    }
    
    function deactivateTutor(uint256 _tutorId) external onlyOwner {
        tutors[_tutorId].isActive = false;
    }
}



